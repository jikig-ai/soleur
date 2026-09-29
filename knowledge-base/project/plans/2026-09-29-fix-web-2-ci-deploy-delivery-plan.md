---
title: "fix: web-2 never receives ci-deploy.sh updates after birth — per-host deploy-pipeline delivery + parity assertion"
type: fix
date: 2026-09-29
slug: web-2-ci-deploy-delivery
branch: feat-one-shot-9151-web2-ci-deploy-delivery
issue: 9151
lane: cross-domain
brand_survival_threshold: none
---

## Overview

**Deepened:** 2026-09-29 via `deepen-plan` (sequential fallback — no Task
fan-out in this harness; halt gates 4.5–4.11 executed mechanically, all green;
verify-the-negative and self-review passes run inline). Key deepen findings:
(1) `apply-deploy-pipeline-fix.yml` deliberately excludes `server.tf` from
`paths:` (R13 comment) — the sibling still applies because the diff touches
`ci-deploy.sh`/`cat-deploy-state.sh`, both listed; (2)
`apply-web-platform-infra.yml` fires on `infra/**` and must never `-target`
the sibling — recorded under Phase 3/NFR5; (3) `triggers_replace` needs the
sentinel convention (`terraform_data` cannot see provisioner-body drift) and
must exclude `local.webhook_doppler_token_env`; (4) the credential-exclusion
became a mechanical assertion inside the provisioner-parity guard (Guard 2,
mutation row 6); (5) Downtime & Cutover assessed — `try-restart webhook` on a
weight-0 standby is the nearest downtime-class op, with a named casualty class
(dropped one-shot `deploy-peer` POST, self-reporting via the parity check).

web-2 (`hcloud_server.web["web-2"]`, server 167390740, born 2026-09-25) receives
`/usr/local/bin/ci-deploy.sh` exactly once, from its birth cloud-init, because
`hcloud_server.web` carries `ignore_changes = [user_data]` and the re-delivery
channel (`terraform_data.deploy_pipeline_fix` → `push-infra-config.sh` →
`https://deploy.<base>/hooks/infra-config`) terminates on web-1 only — the
tunnel ingress `deploy.` and `ssh.` both resolve to `web_hosts["web-1"]`.
Measured 2026-09-28 (#9151): web-2's deploys still pull the cosign verifier
from `ghcr.io` while web-1 pulls from `gcr.io`, and web-2 never runs the
`IMAGE_FRESHNESS` gate shipped by PR #9156. This plan adds a per-host
re-delivery path for web-2 (the #7103-B4 pre-decided guarded `terraform_data`
sibling shape) and a no-SSH sha-parity assertion readable on Better Stack and
the deploy-status endpoint, so "web-2 holds a stale deploy script" stops being
silent.

## Research Insights

### Premise Validation (Phase 0.6 — checked live 2026-09-29)

| Cited premise | Result |
|---|---|
| #9151 open | OPEN — title: "web-2 never receives ci-deploy.sh updates after birth"; comment asks for `IMAGE_FRESHNESS: ok` row from `host_name=soleur-web-2` in Better Stack as close-verification |
| #7103 open | OPEN — tracker; item B4 pre-decides "a guarded `terraform_data` sibling with `connection.host = …["web-2"]`, NOT fanning a full-prd token to a peer over the private net" |
| #6428 / PR #9156 | Issue CLOSED; PR MERGED 2026-09-28 — added the `IMAGE_FRESHNESS` gate to `ci-deploy.sh` |
| `apps/web-platform/infra/server.tf`, `apply-deploy-pipeline-fix.yml`, `apply-web-platform-infra.yml`, `scripts/betterstack-query.sh` | All present on `origin/main` |
| `hcloud_server.web` `ignore_changes=[user_data]` | Confirmed (server.tf `lifecycle` block) |
| web-2 live shape | Hetzner API (2026-09-29): id 167390740, `soleur-web-2`, public `204.168.189.200`, private `10.0.1.11` attached and running (matches `var.web_hosts` default) |
| web-2 SSH host key | Captured 2026-09-29 via `ssh-keyscan` on the public IP from an egress (`82.67.29.121`) that IS in `var.admin_ips` (Doppler `prd_terraform/ADMIN_IPS`) — the same trust channel `scripts/capture-web-1-host-key.sh` prescribes. `ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMjxVxOs1Oec2CiYkQUc0N3XhaX5xXwzI73SKxA3Tr5VjEnXM4Yu5EjgpZJAL65zb/J0n0JgB48AEn0PVh5JsXE=` |

**Correction to the issue's framing:** `terraform_data.deploy_pipeline_fix` has
NO `connection`/`host` — it is a `local-exec` provisioner running
`push-infra-config.sh`, which POSTs to `https://deploy.<base>/hooks/infra-config`.
The web-1 pinning lives in `tunnel.tf`'s ingress rules (`deploy.` →
`http://${web_hosts["web-1"].private_ip}:9000`, `ssh.` →
`ssh://${web_hosts["web-1"].private_ip}:22`), not in the resource itself. The
issue's "for_each over the web hosts" direction therefore cannot work as written
— a `for_each` local-exec cannot reach web-2 without a per-host route. #7103's
pre-decided shape (an SSH `terraform_data` sibling with `connection.host =
web-2`) is the coherent reading and is what this plan implements.

### Property List (Phase 0.6b)

- P1: web-2's deploy-pipeline file set tracks repo `main` — edits reach web-2
  via the owning apply workflow, not only at birth.
- P2: per-host delivered-sha parity is observable without SSH (deploy-status
  field and/or a Better Stack-readable field).
- P3: post-merge, a real web-2 deploy logs `IMAGE_VERIFY: ok` with the gcr.io
  cosign ref AND `IMAGE_FRESHNESS: ok` under `host_name=soleur-web-2`.
- P4: no new credential-transit path — the full-prd Doppler token is not fanned
  to a peer over the private net (#7103's explicit constraint).
- P5: every host write flows through the existing apply guards (host_creates
  halt, non-terraform_data delete guard, shared `terraform-apply-web-platform-host`
  serializer, `if: always()` bridge teardown).

### Mechanism minimality check (Phase 0.6b)

| Proposed mechanism | Property | Already covered by? | Verdict |
|---|---|---|---|
| `for_each = var.web_hosts` on `deploy_pipeline_fix` | P1 | Nothing reaches web-2 today | CUT as written — resource is local-exec; per-host reach requires a per-host route (see Correction above). Re-expressed as an SSH sibling |
| Guarded `terraform_data` sibling w/ `connection.host = web-2` | P1, P5 | `disk_monitor_install` + 17 siblings prove the SSH shape; `infra_config_handler_bootstrap` proves the dual-context (CI tunnel / operator agent) connection | KEEP — pre-decided shape |
| Parity assertion via deploy-status endpoint | P2 (web-1) | `/hooks/infra-config-status` already reports per-file sha256 (`files[].sha256`) for web-1; `/hooks/deploy-status` merges `ci-deploy.state` | KEEP — extend `cat-deploy-state.sh` with a live `ci_deploy_sha256` field |
| Parity assertion via Better Stack field | P2 (web-2) | `logger -t ci-deploy` lines ship to the shared Logs source with per-host `host_name` (vector.toml `@@HOST_NAME@@`); `betterstack-query.sh` reads them | KEEP — emit `DEPLOY_SCRIPT_SHA` per deploy on every host |
| New per-host monitoring daemon on web-2 | P2 | The two channels above suffice; a daemon would need its own delivery path | CUT — chicken-and-egg, adds a third emitter for one field |
| New tunnel ingress `deploy-web-2.`/`ssh-web-2.` + CF Access app + DNS record | P1 route | NOT needed under the chosen shape — the git-data precedent (ADR-220) reaches a second private-net host THROUGH the existing `ssh.` bridge via a `-L`/`-W` forward off web-1 | CUT from primary; recorded as fallback |

### Key file map (verified against `origin/main`)

- `apps/web-platform/infra/server.tf` — `hcloud_server.web` (`for_each =
  var.web_hosts`, `ignore_changes=[user_data, ssh_keys, image,
  placement_group_id]`), 18 SSH `terraform_data` provisioners all pinned
  `connection.host = hcloud_server.web["web-1"].ipv4_address` +
  `host_key = local.web_1_ssh_host_key`; `local.web_1_ssh_host_key` regex-pin
  reading `web-1-ssh-host-key.pub`; `terraform_data.deploy_pipeline_fix`
  (local-exec, `depends_on = [apparmor_bwrap_profile,
  infra_config_handler_bootstrap]`); `terraform_data.web_1_host_key_probe`.
- `apps/web-platform/infra/tunnel.tf` — ONE tunnel, THREE ingress rules
  (`deploy.`, `ssh.`, `registry.`), all origin-relative to private IPs; CF
  Access apps `deploy` + `ssh` with dedicated service tokens.
- `apps/web-platform/infra/dns.tf` — `cloudflare_record.{deploy,ssh,registry}`
  CNAMEs → `<tunnel>.cfargotunnel.com`.
- `apps/web-platform/infra/ci-deploy.sh` — `LOG_TAG="ci-deploy"`,
  `COSIGN_IMAGE` gcr.io pin, `IMAGE_VERIFY`/`IMAGE_FRESHNESS` emit functions,
  `fan_out_to_peers()` POSTs `http://<peer>:9000/hooks/deploy-peer`
  (`SOLEUR_DEPLOY_PEERS`, shared `webhook_deploy_secret`, never re-fans),
  `write_state` → `/var/lock/ci-deploy.state`.
- `apps/web-platform/infra/cat-deploy-state.sh` — `/hooks/deploy-status`
  reporter; merges state file + `host_id` + `services.*` fields.
- `apps/web-platform/infra/infra-config-apply.sh` — webhook handler; 20-entry
  `FILE_MAP` writes payload files and records per-file `sha256` into
  `/var/lock/infra-config-apply.state` (served by `/hooks/infra-config-status`).
- `apps/web-platform/infra/push-infra-config.sh` — builds the base64 payload
  incl. `SOLEUR_DOPPLER_TOKEN_B64`; POSTs to `deploy.${APP_DOMAIN_BASE}`.
- `apps/web-platform/infra/infra-config-verify.sh` + `infra-config-gate.sh` —
  post-apply adjudication (count invariant, per-file sha content assert,
  frame-freshness pin, DPF_REPLACED sensor).
- `.github/actions/cf-tunnel-ssh-bridge/` — composite: cloudflared install
  (SHA-pinned), Doppler `CI_SSH_ACCESS_TOKEN_*` pull, `cloudflared access tcp
  --hostname ssh.<base> --url 127.0.0.1:2222`, `iptables -t nat OUTPUT
  REDIRECT` of `SERVER_IP:22`, `write-known-hosts.sh` web-1 pin writer,
  caller-side teardown contract.
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — asserts ALL
  SSH provisioners are web-1-pinned and none `for_each`'d (FLOOR_RESOURCES=18,
  FLOOR_DESTS=57, ALLOWED_HOST_KEYS={`local.web_1_ssh_host_key`}); its header
  explicitly anticipates this change: "If CI genuinely gained a route to
  web-2, the tunnel connector, the firewall and the -target lists must change
  FIRST, and this check with them."
- `plugins/soleur/test/terraform-target-parity.test.ts` — every SSH-provisioned
  resource must appear in a `-target=` ∪ allowlist union; no `terraform_data`
  may be targeted before the bridge step.
- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` — TRIGGER_FILES /
  DPF_REGEX / on.push.paths / FILE_MAP lockstep.
- `apps/web-platform/infra/web-1-host-key-local.test.sh` + mutation battery —
  pin-file shape guard (model for a `web-2` twin).
- `scripts/capture-web-1-host-key.sh` — capture contract (admin_ips egress,
  refuses CI, single-ECDSA pin through `write-known-hosts.sh`).
- `apps/web-platform/infra/vector.toml` — Source-4 `SYSLOG_IDENTIFIER`
  allowlist includes `ci-deploy`; `.host_name = "@@HOST_NAME@@"` rendered
  per-host (`soleur-web-platform` / `soleur-web-2`).

### Institutional learnings applied

- `hr-ssh-diagnosis-verify-firewall` / plan-network-outage-checklist — SSH
  trigger matched; `## Hypotheses` carries L3→L7 verification entries.
- ADR-114 — ingress must be origin-relative; "do not repoint connection hosts"
  constraint is extended, not violated, by ADDING a web-2 route.
- ADR-237 — host keys are committed pins; web-2 gets `web-2-ssh-host-key.pub` +
  `local.web_2_ssh_host_key`, never TOFU.
- ADR-220 — CI reaches a second private host through web-1: the `ssh.` tunnel
  bridge plus an `ssh -L` forward to the peer's private IP is the established
  pattern (git-data uses `-W 10.0.1.20:22`), avoiding any new CF surface.
- #6594 / #7220 — latched false-green apply class: the web-2 sibling's
  remote-exec must assert on-host `sha256sum`, not merely write.
- `2026-05-20-terraform-go-ssh-client-ignores-ssh-config-multi-agent-catch.md` —
  connection.host stays the literal `ipv4_address`; the iptables redirect is
  transparent to the Go client.
- Community discovery: no uncovered stack signatures (Terraform/bash/bun — all
  covered); functional-overlap and external-research fan-outs skipped — this is
  repo-internal IaC with dense local precedent (Task-spawning agents
  unavailable in this harness; assessment done inline).

# fix: web-2 never receives ci-deploy.sh updates after birth

## Problem Statement

`hcloud_server.web` carries `ignore_changes = [user_data]`, so cloud-init writes
`/usr/local/bin/ci-deploy.sh` to a web host exactly once — at birth. The
re-delivery channel for that file (`terraform_data.deploy_pipeline_fix` →
`push-infra-config.sh` → `https://deploy.<base>/hooks/infra-config` →
`infra-config-apply.sh` `FILE_MAP`) terminates on web-1 alone, because the
`deploy.` tunnel ingress is origin-pinned to `web_hosts["web-1"].private_ip` and
the push script has no per-host addressing. Three `ci-deploy.sh`-affecting
commits landed after web-2's 2026-09-25 birth (`6d08cca86d`, `ec19040203`,
`e7fa71b585`); none reached web-2. Consequences measured in #9151: web-2 still
pulls the cosign verifier from `ghcr.io` (web-1 pulls from `gcr.io`), web-2
never runs the `IMAGE_FRESHNESS` gate, and nothing reports the drift. The same
blindness holds for every deploy-pipeline artifact web-1 receives through that
channel, and — one layer down — for web-2's birth-frozen `infra-config-apply.sh`
handler and `hooks.json`, which no channel can refresh either.

## Proposed Solution

Follow #7103's pre-decided shape: a **guarded `terraform_data` sibling**,
`deploy_pipeline_fix_web2`, whose `connection.host` is
`hcloud_server.web["web-2"].ipv4_address`, delivering the deploy-pipeline file
set to web-2 over root SSH with positive post-write sha256 assertions — the
same shape `infra_config_handler_bootstrap` uses for web-1.

**Reconciliation of the two fix directions.** #9151's "make the push per-host"
(`for_each` on `deploy_pipeline_fix`) is infeasible as written — the resource is
`local-exec` POSTing to a single hostname; a `for_each` would need a per-host
ingress anyway. #7103's `connection.host = web-2` sibling is therefore the
controlling decision. Where the letters differ, the pre-decided shape wins: the
sibling is SSH-provisioned, and the full-prd Doppler token is deliberately NOT
in its delivery set (web-2's `/etc/default/soleur-doppler-token` refresh remains
#7103-B4 scope).

**CI reachability without a new Cloudflare surface.** The `ssh.` bridge already
gives the runner a pinned root-SSH session to web-1. Following the ADR-220
git-data precedent (a second private-net host reached *through* web-1 via
`direct-tcpip`/`-W`), the workflow adds a local forward
`ssh -N -L 127.0.0.1:2223:10.0.1.11:22` inside that pinned session and a second
`iptables` REDIRECT of web-2's *public* IPv4 `:22` → `127.0.0.1:2223`.
Terraform's `connection.host` stays the literal public address (the Go client
ignores ssh_config — the redirect is transparent), the inner SSH session to
web-2 is pinned by `host_key = local.web_2_ssh_host_key` end-to-end, and the
bastion hop itself is pinned to web-1's committed key. No new tunnel ingress,
CF Access app, service token, or DNS record is created. Fallback if the `-L`
forward proves unreliable at work time: a dedicated `ssh-web-2.` ingress
(`ssh://${var.web_hosts["web-2"].private_ip}:22`) + CF Access policy bound to
the existing `ci_ssh` token + CNAME — recorded under Alternatives.

**Host-key pin.** `apps/web-platform/infra/web-2-ssh-host-key.pub` ships in
this PR with the ECDSA-P256 key captured 2026-09-29 from an admin_ips-allowlisted
egress (evidence in Research Insights; re-verify at work time against a fresh
`ssh-keyscan`). `local.web_2_ssh_host_key` mirrors the web-1 regex/`one()` shape.

**Parity assertion (no SSH).** Three layers: (a) `cat-deploy-state.sh` reports a
live `ci_deploy_sha256` field — web-1's `/hooks/deploy-status` becomes directly
assertable; (b) `ci-deploy.sh` emits `DEPLOY_SCRIPT_SHA sha256=<sha of
/usr/local/bin/ci-deploy.sh>` at startup on every host — readable on Better
Stack per `host_name` via `scripts/betterstack-query.sh`; (c) the sibling's
`remote-exec` asserts `sha256sum` on-host equals the Terraform-computed
`filesha256` at apply time. A new `scripts/check-deploy-script-parity.sh`
compares the repo sha against web-1's status field and web-2's last Better
Stack emission; the apply workflow's verify step runs it.

## Technical Approach

### Architecture

- Delivery: `terraform_data.deploy_pipeline_fix_web2` — `provisioner "file"` for
  the script set + `remote-exec` for permissions, `daemon-reload`, and sha256
  assertions. `triggers_replace = sha256(join(",", [per-file hashes …,
  local.hooks_json hash, hcloud_server.web["web-2"].id,
  file("web-2-ssh-host-key.pub")]))` — the server-id input re-fires the delivery
  on a web-2 *replacement* (the cattle model; the fresh-host trap documented at
  `docker_seccomp_config`), the pin-file input re-fires on re-key.
- Delivered set: ONE sibling carries the union of (a) the `FILE_MAP` members
  that are not secret-bearing — `ci-deploy.sh`, `ci-deploy-wrapper.sh`,
  `webhook.service`, `cat-deploy-state.sh`, `canary-bundle-claim-check.sh`,
  rendered `hooks.json`, `cat-infra-config-state.sh`,
  `inngest-enumerate-reminders.sh`, `inngest-rearm-reminders.sh`,
  `inngest-wiped-volume-verify.sh`, `cat-inngest-verify-state.sh`,
  `inngest-inventory.sh`, `git-lock-chardevice-sweep.sh`,
  `inngest-registry-probe.sh`, `inngest-doublefire-probe.sh`, and the four
  `10-*-doppler-token.conf` drop-ins (vector, inngest-heartbeat,
  inngest-server, inngest-redis) — plus (b) the bootstrap set
  (`infra-config-apply.sh`, `infra-config-install.sh`,
  `deploy-inngest-bootstrap.sudoers`) so web-2's management plane is no longer
  birth-frozen. One resource, not a web-1-style two-resource split: web-1 needs
  `infra_config_handler_bootstrap` as a distinct bridge because the webhook
  push cannot carry the handler that serves it; an SSH sibling has no such
  constraint. EXCLUDED: `SOLEUR_DOPPLER_TOKEN` (the full-prd credential —
  #7103's constraint; SSH transit is not "peer fan-out" but the scope boundary
  is kept deliberately; web-2's copy was rendered at birth via
  `soleur_doppler_token_env_b64`). `hooks.json` embeds `webhook_deploy_secret`;
  it is included because the sibling's root-SSH channel strictly dominates that
  secret's blast radius and excluding it would leave web-2's hook surface
  frozen — the defect this fixes. It is written via base64 remote-exec, exactly
  as `infra_config_handler_bootstrap` does (never a `file` `source`/`content`
  argument — the sensitive value must not appear in command argv).
- `triggers_replace`: `sha256(join(",", [...]))` over `file()` of every
  delivered repo file, `local.hooks_json`, `hcloud_server.web["web-2"].id`
  (the fresh-host/cattle-replacement re-fire — `docker_seccomp_config`
  precedent), `file("web-2-ssh-host-key.pub")` (re-key re-fire), and a
  **sentinel string** bumped whenever the inline `remote-exec` list changes
  (`terraform_data` does not detect provisioner-body drift — the convention
  `deploy_pipeline_fix`'s header documents). Exclusions vs. web-1's hash:
  `local.webhook_doppler_token_env` (the token is not delivered — a rotation
  must NOT re-fire web-2 delivery, because nothing the sibling carries changes;
  the web-1 push re-fires to deliver the token itself), and
  `push-infra-config.sh` (runner-side only; never lands on a host). The
  pin-file hash means `web-2-ssh-host-key.pub` must join the
  `apply-deploy-pipeline-fix.yml` `paths:` list and TRIGGER_FILES so a re-key
  fires the apply (lockstep asserted by `ship-deploy-pipeline-fix-gate.test.ts`
  — verify at work time whether its triggers_replace sweep reaches the new
  resource; if it only reads `deploy_pipeline_fix`'s block, still add the path
  deliberately).
- No `depends_on`: web-1's `deploy_pipeline_fix → infra_config_handler_bootstrap`
  edge exists because the push flows THROUGH the handler (#5515). Both web-2
  deliveries are direct SSH writes in one resource — file provisioners complete
  before `remote-exec` runs, so ordering is internal and no edge is needed.
- Connection `timeout = "5m"`: the existing 18 siblings carry none (the parity
  guard documents this), but a dead web-2 would otherwise burn the whole run's
  SSH dial retries; the guard's contract is about destinations/host-pinning,
  not per-resource timeouts, so the new resource may set one.
- Observability emit: `DEPLOY_SCRIPT_SHA` line near `SOLEUR_DEPLOY_INVOCATION`
  in `ci-deploy.sh`; `ci_deploy_sha256` in `cat-deploy-state.sh` output.
- Assertion: `scripts/check-deploy-script-parity.sh` (repo sha vs web-1 status
  field vs per-host Better Stack emissions); invoked from
  `apply-deploy-pipeline-fix.yml`'s post-apply verify step for the web-1 arm and
  as the documented operator/CI probe for web-2.

### Implementation Phases

#### Phase 1 — Host-key pin + HCL plumbing

- Commit `apps/web-platform/infra/web-2-ssh-host-key.pub` (header + single
  ECDSA-P256 line, written through `.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh`
  semantics; capture evidence recorded in the file header).
- `server.tf`: `local.web_2_ssh_host_key` (twin regex/`one()` shape reading the
  new pin file), `output "web_2_server_ip"` in `outputs.tf`.
- New guard twin `apps/web-platform/infra/web-2-host-key-local.test.sh`
  (clone of the web-1 pin-shape test).
- Generalize `scripts/capture-web-1-host-key.sh` → shared
  `scripts/capture-web-host-key.sh <name> <public-ipv4>` (or add a
  `capture-web-2-host-key.sh` twin — pick the shape that keeps the existing
  script's callers/runbook links byte-stable; ADR-237 names the web-1 path).
- Success: `web-2-host-key-local.test.sh` green; `terraform plan` resolves the
  new local.

#### Phase 2 — The sibling resource

- `server.tf`: `resource "terraform_data" "deploy_pipeline_fix_web2"` —
  dual-context connection (`private_key = var.ci_ssh_private_key`,
  `agent = var.ci_ssh_private_key == null`, `host_key =
  local.web_2_ssh_host_key`, `script_path = "/root/…-%RAND%.sh"` per the #8706
  secret-residue rule), `provisioner "file"` per delivered artifact +
  `remote-exec` with `set -e`, per-file `sha256sum` assertions against
  Terraform-interpolated `filesha256()`/`sha256(local.hooks_json)` values,
  `chmod`/`chown` matching cloud-init parity, `systemctl daemon-reload`, and
  `systemctl try-restart webhook` (webhook serves the new hooks.json on the next
  connection; restart is safe — the SSH path is independent of the webhook
  process, same reasoning as `infra_config_handler_bootstrap`).
- `triggers_replace` per Architecture above; `depends_on = []` — none needed
  (no web-1 ordering dependency; keep the resource independent so a web-1 push
  failure cannot mask web-2 delivery and vice versa — but see Risk R4 on
  `deploy_pipeline_fix`'s `depends_on` semantics being deliberately mirrored if
  review finds the webhook-before-delivery ordering load-bearing for web-2 too;
  web-2 has no bridge resource to order against, so a literal mirror is
  impossible).
- Success: `terraform plan` shows the resource create-only on web-2; zero
  changes to web-1 resources.

#### Phase 3 — CI reachability + workflow wiring

- `apply-deploy-pipeline-fix.yml`: after the existing CF Tunnel SSH bridge step
  (which leaves `cloudflared access tcp` on `127.0.0.1:2222` and the pinned
  web-1 known_hosts in place), add a "web-2 forward" step that:
  1. writes `DEPLOY_SSH_PRIVATE_KEY` to a 0600 tempfile (the workflow already
     exports it for Terraform as `TF_VAR_ci_ssh_private_key`; the forward needs
     it as a file for `ssh -i`),
  2. runs `ssh -N -o ExitOnForwardFailure=yes -o StrictHostKeyChecking=yes -o
     UserKnownHostsFile=<bridge known_hosts> -i <keyfile>
     -L 127.0.0.1:2223:10.0.1.11:22 root@127.0.0.1 -p 2222` in background, then
     polls the listener with a bounded loop (`timeout`-bounded, ≤30 s total) —
     never an unbounded wait (CI network-call discipline),
  3. `iptables -t nat -A OUTPUT -d $WEB_2_IP -p tcp --dport 22 -j REDIRECT
     --to-ports 2223` where `WEB_2_IP=$(terraform output -raw web_2_server_ip)`
     — read AFTER init so the output exists.
- Extend the `if: always()` teardown to delete the second NAT rule and kill the
  forward PID (`kill %`/stored `$!`), tolerant of the step never having run
  (pre-forward failure must not fail the teardown itself).
- Add `-target=terraform_data.deploy_pipeline_fix_web2` to BOTH the plan and
  apply invocations. `-target` transitivity pulls
  `hcloud_server.web["web-2"]` into the plan graph — the host exists in state
  and must show zero actions (NFR1); a `create` there halts via the shared
  destroy-guard regardless.
- **#8705-class sweep — every apply workflow this diff can fire:**
  `apply-deploy-pipeline-fix.yml` fires on merge because the diff touches
  `ci-deploy.sh`/`cat-deploy-state.sh` (both in its `paths:`; `server.tf`
  stays deliberately absent per its R13 comment). `apply-web-platform-infra.yml`
  ALSO fires (its `paths:` is `apps/web-platform/infra/**`) and its
  `-target`-scoped plans will evaluate `local.web_2_ssh_host_key`'s `file()`
  read at plan time — the pin file is committed in this PR, so that resolves —
  but the sibling is NOT in its `-target` sets and must not be added there (its
  bridge carries no web-2 forward). Add a comment at the resource and, if the
  union test requires it, an allowlist entry naming `apply-deploy-pipeline-fix`
  as the sibling's sole carrier.
- `terraform-target-parity.test.ts` requires every SSH-provisioned resource in
  the `-target=` ∪ allowlist union — covered by the DPF `-target`; its
  "no terraform_data before the bridge" invariant is satisfied because the
  forward step precedes plan/apply. Verify at work time whether the union is
  per-workflow or across both; if per-workflow, the sibling additionally needs
  an apply-web-platform-infra allowlist entry (never a bare `-target` there).
- Success: workflow run shows the web-2 apply green; teardown removes both NAT
  rules.

#### Phase 4 — Parity emission + assertion

- `ci-deploy.sh`: emit `DEPLOY_SCRIPT_SHA sha256=$(sha256sum
  /usr/local/bin/ci-deploy.sh | awk '{print $1}')` via `logger -t ci-deploy`
  at startup (adjacent to `SOLEUR_DEPLOY_INVOCATION`).
- `cat-deploy-state.sh`: add `ci_deploy_sha256` (live `sha256sum`, `|| ""` on
  failure — an absent field is distinguishable from an old script; mirror the
  `resolve_host_id` `|| true` contract).
- New `scripts/check-deploy-script-parity.sh`: `sha256sum` the repo file; read
  web-1 via `https://deploy.<base>/hooks/deploy-status` (`curl --max-time 20`,
  HMAC `X-Signature-256` + CF Access headers — same env the verify step already
  builds); read each host's newest `DEPLOY_SCRIPT_SHA` from Better Stack via
  `scripts/betterstack-query.sh` (needs `doppler run -p soleur -c
  prd_terraform`); exit 0 on parity, non-zero listing divergent/absent hosts.
  Host enumeration comes from `var.web_hosts` in `variables.tf`, never a
  literal list. `--self-test` mode (no credentials, no network) asserts the
  emit marker + field exist and the host set enumerates — prints `ok`.
- `apply-deploy-pipeline-fix.yml` verify step: invoke the web-1 arm of the
  parity script (endpoint read) after the existing infra-config verify; web-2's
  apply-time assert is inside the sibling's `remote-exec` (Phase 2).
- Success: post-merge deploy of any later ci-deploy.sh change emits
  `DEPLOY_SCRIPT_SHA` from both host_names and the script exits 0.

#### Phase 5 — Guard/test updates + records

- `web-host-provisioner-parity.test.sh`: teach the web-1-pin assertion the
  web-2 sibling class (web-2-named sibling pins `web["web-2"]` +
  `local.web_2_ssh_host_key`; all others stay web-1-pinned); bump
  FLOOR_RESOURCES 18→19 and FLOOR_DESTS accordingly; extend
  ALLOWED_HOST_KEYS + the dials-web-1 rule with a dials-web-2 counterpart;
  extend `web-host-provisioner-parity-mutation.test.sh` with a mutation row for
  the sibling (e.g., sibling without host_key → RED; sibling repointed to
  web-1 → RED).
- `ci-deploy.test.sh` / `cat-deploy-state.test.sh`: cover the new
  `DEPLOY_SCRIPT_SHA` emit + `ci_deploy_sha256` field.
- `ship-deploy-pipeline-fix-gate.test.ts` + `ship/SKILL.md`
  DEPLOY_PIPELINE_FIX_TRIGGERS: verify whether the sibling's `triggers_replace`
  sweep is covered by the gate's extractor (it scans server.tf
  triggers_replace — confirm scope at work time; if it sweeps all resources,
  add the sibling's file set or scope it out deliberately with a comment).
- `terraform-target-parity.test.ts` / destroy-guard jq filter: confirm the new
  `-target=` and resource classify correctly (no new counters needed — it is a
  `terraform_data` replace, which the filter already tolerates).
- ADR-114 amendment note + ADR-237 §(web-2 pin) touch-up, C4 model edits (see
  Architecture Decision section).
- Success: `bun test` / `run-registered-suites.sh` green; parity guard's
  mutation battery green.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| `for_each = var.web_hosts` on `deploy_pipeline_fix` | Resource is local-exec POSTing to one hostname; per-host instances would still need per-host routes, and it would restructure web-1's proven path for zero benefit there |
| Second tunnel ingress `deploy-web-2.` → `http://10.0.1.11:9000` + local-exec push twin | Works today (web-2's birth handler covers FILE_MAP), but makes web-2's delivery permanently hostage to its birth-frozen `infra-config-apply.sh`/`hooks.json` — the same defect one layer down, with no self-heal (the handler cannot deliver itself; #4804/#4811). Also opens a second public webhook surface. Kept as fallback if the SSH route fails at work time |
| New `ssh-web-2.` ingress + CF Access app + CNAME | Clean SSH route but adds three new Cloudflare objects; the `-L`-through-web-1 pattern (ADR-220) reaches web-2 with zero new CF surface — strictly smaller blast radius. Fallback if the forward proves unreliable |
| Peer fan-out through web-1 (`deploy-peer`-style relay for infra-config) | Explicitly rejected by #7103 — fannning the push payload (which embeds the full-prd Doppler token) to a peer over the private net invents a credential-transit path |
| Wait for web-2's next rebuild to pick up current scripts | The defect class is exactly "birth-frozen until replaced"; #7103 B4 wants the re-delivery path regardless of rebuild cadence |
| Terraform-minted host key for web-2 (git-data D1 pattern) | Requires installing the key on a live host — circular (the delivery channel is what's being built). The committed-pin pattern (web-1 precedent) applies to hosts that already exist |

## Hypotheses

(Triggered by the SSH/firewall patterns in the feature description — L3→L7 order)

1. **L3 firewall allowlist.** web-2's public :22 is allowlisted to
   `var.admin_ips`; operator egress `82.67.29.121` is present (Doppler
   `prd_terraform/ADMIN_IPS` read 2026-09-29; `ssh-keyscan 204.168.189.200`
   succeeded). CI does not traverse this path — it uses the tunnel bridge.
   [verified: keyscan output + admin_ips list]
2. **L3 DNS/routing.** No new DNS needed in the primary design — the web-2 leg
   rides the existing `ssh.` ingress to web-1 plus a private-net forward.
   web-2's private NIC is attached at 10.0.1.11 (Hetzner API, 2026-09-29).
   [verified]
3. **L7 TLS/proxy.** The `ssh.` CF Access app + `ci_ssh` service token
   authenticate the bridge; the web-2 hop inherits it (the `-L` session is the
   existing authenticated channel). A fallback `ssh-web-2.` ingress would need
   its own Access policy — bound to the same `ci_ssh` token. [verified by
   config read; runtime proven at first apply]
4. **L7 application.** web-2's sshd listens on the private NIC (default
   `ListenAddress`; hardening conf restricts auth, not bind) and its webhook
   already serves `deploy-peer` fan-out on :9000 — web-2's deploys ran the
   2026-09-28 releases (Better Stack evidence in #9151). web-2's root
   `authorized_keys` carries the CI deploy pubkey via cloud-init
   (`ci_ssh_public_key_openssh` in the templatefile map, in effect since before
   web-2's birth). Residual: fail2ban on web-2 could ban web-1's private IP
   after repeated auth failures — the forward must authenticate cleanly or not
   retry-storm (Risk R5). [verified by config read + issue evidence]

### Network-Outage Deep-Dive (deepen-plan 4.5 — fired on SSH trigger)

Layer-by-layer verification status for the new CI→web-2 leg:

| Layer | Status | Artifact |
|---|---|---|
| L3 firewall (public path, operator keyscan) | VERIFIED | egress `82.67.29.121` ∈ `ADMIN_IPS` (Doppler `prd_terraform`, 2026-09-29); `ssh-keyscan 204.168.189.200` returned ECDSA-P256 |
| L3 DNS/routing | VERIFIED | no new DNS needed — the leg rides the existing `ssh.` ingress to web-1, then the private net (web-2 NIC live at 10.0.1.11, Hetzner API 2026-09-29) |
| L7 TLS/proxy (CI path) | VERIFIED | existing CF Access `ssh` app + `ci_ssh` service token authenticate the bridge; the `-L` session inherits them (no new Access object) |
| L7 application | VERIFIED-BY-PRECEDENT | web-1's sshd already answers direct-tcpip forwards for the ADR-220 git-data channel (`-W 10.0.1.20:22`, "Transport LIVE, measured", C4 model, accepted 2026-09-27); web-2 sshd on private NIC confirmed by config + webhook liveness evidence |
| Work-time belts | PENDING | `command -v ssh` on the runner (ubuntu-latest ships openssh-client — not currently used by the bridge, which runs cloudflared only); `sshd -T` `allowtcpforwarding` read via the pinned channel before first apply |

No gap requires a new production surface before implementation; the one
unverified-by-measurement item (web-1 `AllowTcpForwarding`) has a live
precedent and a work-time probe with a named fallback (`ssh-web-2.` ingress).

## Downtime & Cutover (deepen-plan 4.55 — assessed)

**Nearest downtime-class operation:** `systemctl try-restart webhook` on
web-2 inside the sibling's remote-exec. web-2 is a serving-weight-0 standby
outside the app A record — no user traffic transits it, so no user-facing
surface goes offline. The one in-flight casualty class is a `deploy-peer`
POST from web-1 arriving during the bounce window: `fan_out_to_peers` is
one-shot (logs accept/not-accepted, no retry), so a dropped call leaves web-2
on its previous deploy until the next deploy — a degraded, self-reporting
state (the parity assertion then reads drift, exactly what it exists for).
Zero-downtime alternatives evaluated: (a) restart-free delivery — rejected,
the new `hooks.json` only takes effect on listener start, and deferring
activation recreates the "delivered but inert" defect class (#7103 R2);
(b) ordering the restart last with `is-active` assertion + a bounded
`systemctl is-failed` rollback report — adopted. Residual downtime: none on
any user-serving surface; ~sub-second listener gap on web-2's :9000 with a
named failure mode. No maintenance window or operator sign-off needed.

## Files to Create

- `apps/web-platform/infra/web-2-ssh-host-key.pub` — committed ECDSA-P256 pin
- `apps/web-platform/infra/web-2-host-key-local.test.sh` — pin-shape guard twin
- `scripts/check-deploy-script-parity.sh` — no-SSH parity assertion
- `scripts/capture-web-host-key.sh` (generalized) OR
  `scripts/capture-web-2-host-key.sh` (twin) — recapture path for re-key/replace

## Files to Edit

- `apps/web-platform/infra/server.tf` — `local.web_2_ssh_host_key` +
  `terraform_data.deploy_pipeline_fix_web2`
- `apps/web-platform/infra/outputs.tf` — `web_2_server_ip` output
- `apps/web-platform/infra/ci-deploy.sh` — `DEPLOY_SCRIPT_SHA` emit
- `apps/web-platform/infra/cat-deploy-state.sh` — `ci_deploy_sha256` field
- `apps/web-platform/infra/ci-deploy.test.sh`,
  `apps/web-platform/infra/cat-deploy-state.test.sh` — coverage
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` +
  `web-host-provisioner-parity-mutation.test.sh` — web-2 sibling class, floors,
  ALLOWED_HOST_KEYS, mutation rows
- `.github/workflows/apply-deploy-pipeline-fix.yml` — web-2 forward step,
  second NAT rule + teardown, `-target=` addition, parity-check invocation
- `plugins/soleur/test/terraform-target-parity.test.ts`,
  `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` — scope checks /
  allowlist updates if the extractors sweep the new resource
- `knowledge-base/engineering/architecture/decisions/ADR-114-*.md` —
  amendment: CI gains a second SSH route (to web-2 via the web-1 forward), the
  "one SSHable host" constraint is updated
- `knowledge-base/engineering/architecture/diagrams/model.c4` — tunnel
  container description + the `github → hetzner` SSH edge gains the web-2 hop

## Open Code-Review Overlap

- `#2197` (rate-limiter single-instance assumption) mentions `infra/server.tf`
  only hypothetically — a guard against the server resource gaining
  `count`/`for_each`. This plan adds neither to `hcloud_server.web` (the
  `for_each` under discussion was a rejected alternative on `terraform_data`).
  **Disposition: acknowledge** — different concern; the issue stays open.

## Domain Review

**Domains relevant:** Engineering (infra/architecture) — assessed inline
(Task-subagent fan-out is unavailable in this harness; the assessment below is
the orchestrator's, and `plan-review`'s panel covers the same lenses before
`soleur:work`).

### Engineering

**Status:** reviewed
**Assessment:** This is an infrastructure change to the deploy-pipeline
delivery surface: a new SSH-provisioned `terraform_data` sibling reaching a
second production host, a committed SSH host-key pin (ADR-237 pattern), a
workflow bridge extension, and parity telemetry. Architectural blast radius is
bounded — the web-1→web-2 private-net forward reuses an existing authenticated
channel (ADR-220 precedent) and adds no new Cloudflare object. The load-bearing
risks are (a) the parity guard's deliberate "all SSH provisioners are
web-1-pinned" assertion must be taught the sibling class without weakening it,
and (b) the sibling widens CI's root-SSH reach by one host — mitigated by the
committed pin, the dual-context connection, and the existing apply guards.

### Product/UX Gate

**Tier:** none — no user-facing surface; `## Files to Create`/`Edit` contain no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` paths
(mechanical UI-surface override did not fire).

**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — web-2 is a
  serving-weight-0 standby (ADR-143 D2) outside the app A record. The user-visible
  artifact at risk is *deploy integrity*: a botched `ci-deploy.sh` edit shipped
  through the existing web-1 push could break the deploy channel itself (mitigated
  by `write_state`, the deploy-status gate, and the sibling's sha assertions; the
  script edit in this PR is one additive `logger` line).
- **If this leaks, the user's [data / workflow / money] is exposed via:** the
  new CI→web-2 root-SSH leg — bounded by the committed host-key pin
  (`local.web_2_ssh_host_key`), the existing `ci_ssh` CF-Access service token,
  and the fact that delivered payloads contain no new secrets (the webhook
  secret in `hooks.json` is already on web-2; the full-prd Doppler token is
  deliberately excluded).
- **Brand-survival threshold:** `none`
  - `threshold: none, reason:` infra delivery path to a non-serving standby
    host plus additive telemetry; no user data plane is touched and no new
    credential-transit path is created (#7103's constraint is honored by
    exclusion).

## Observability

```yaml
liveness_signal:
  what: "DEPLOY_SCRIPT_SHA logger line emitted by ci-deploy.sh on every deploy, per host (host_name=soleur-web-platform / soleur-web-2 in Better Stack Logs source 2457081), plus ci_deploy_sha256 in the /hooks/deploy-status response"
  cadence: "per deploy + on demand (status endpoint)"
  alert_target: "scripts/check-deploy-script-parity.sh exits non-zero on divergence/absence; surfaced in the apply-deploy-pipeline-fix verify step and readable ad hoc via scripts/betterstack-query.sh"
  configured_in: "apps/web-platform/infra/ci-deploy.sh (emit), apps/web-platform/infra/cat-deploy-state.sh (field), scripts/check-deploy-script-parity.sh (assertion)"

error_reporting:
  destination: "journald → Vector Source 4 (ci-deploy tag is allowlisted) → Better Stack; sibling remote-exec failures fail the terraform apply loudly"
  fail_loud: "apply exits non-zero naming the failed sha assertion; check-deploy-script-parity.sh prints the divergent host and both shas"

failure_modes:
  - mode: "sibling apply fails mid-delivery (partial file set on web-2)"
    detection: "remote-exec sha assertions run after all file provisioners; a partial set fails the apply with the divergent file named"
    alert_route: "workflow failure on apply-deploy-pipeline-fix.yml → release-outcome surfaces"
  - mode: "web-2 script drifts again later (sibling never re-fires)"
    detection: "triggers_replace hashes the delivered files — any repo change re-fires; DEPLOY_SCRIPT_SHA mismatch vs repo sha is visible on Better Stack and caught by check-deploy-script-parity.sh"
    alert_route: "parity script (apply-time + ad hoc)"
  - mode: "DEPLOY_SCRIPT_SHA itself missing (stale pre-emit script still running on web-2)"
    detection: "absence of the marker on the newest web-2 deploy IS the drift signal; the parity script treats a missing marker as non-parity"
    alert_route: "parity script non-zero exit"

logs:
  where: "journald on each host → Vector → Better Stack (soleur_inngest_vector_prd_3); apply logs in the GHA run"
  retention: "Better Stack hot window ~40min + s3 archive via betterstack-query.sh UNION; journald persistent"

discoverability_test:
  command: "bash scripts/check-deploy-script-parity.sh --self-test"
  expected_output: "ok"
```

## Encryption Posture

```yaml
at_rest:
  - store: "terraform.tfstate (R2 backend, apps/web-platform/infra/main.tf)"
    mechanism: "provider-managed:Cloudflare R2 encryption at rest"
    evidence: "existing backend; no new store introduced — the sibling's state is terraform_data metadata only"
    defends_against: "offline snapshot/bucket compromise"
    does_not_defend: "a live AWS key with bucket read (existing exposure, unchanged); the sibling delivers no new secret material — the only interpolated secret it handles is the already-on-host webhook_deploy_secret inside hooks.json"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable: provider-side property, attested by provider docs"

in_transit:
  - connection: "GHA runner -> Cloudflare edge -> web-1 connector -> (SSH -L forward) -> web-2:22"
    enforced_at: "apps/web-platform/infra/server.tf connection block (new sibling) + .github/workflows/apply-deploy-pipeline-fix.yml forward step"
    tls: "QUIC/TLS1.3 to the CF edge (cloudflared access tcp, CF Access service-token authenticated); SSHv2 end-to-end runner->web-2 inside it (host_key pinned to local.web_2_ssh_host_key both hops: web-1 bastion pinned via write-known-hosts.sh known_hosts, web-2 pinned via connection.host_key)"
    cert_verification: "on"
    does_not_defend: "a compromised web-1 sees the forwarded byte stream's SSH handshake metadata (the inner session to web-2 is end-to-end encrypted; web-1 cannot read the key exchange's session keys). A revoked ci_ssh token closes the whole path. Does not defend against a forged web-2 if the committed pin file itself is wrong — the pin is the trust anchor"
    disclosed_as: "not-publicly-claimed"
```

## Guard Contract

### Guard 1 — deploy-script parity assertion (`scripts/check-deploy-script-parity.sh`)

**Property.** Every host expected to run deploys has a recorded
`/usr/local/bin/ci-deploy.sh` sha256 equal to the repo's.

**Assembly.** The assertion quantifies over `var.web_hosts` keys (today web-1,
web-2): web-1's value comes from `deploy.<base>/hooks/deploy-status`
`ci_deploy_sha256` (live on-disk sha, served by `cat-deploy-state.sh`); each
host's value also comes from the newest `DEPLOY_SCRIPT_SHA` line under that
host's `host_name` in Better Stack (`scripts/betterstack-query.sh`). The
chokepoint is the script's per-host loop keyed on the `var.web_hosts` set — the
host list is parsed from `variables.tf`, never hardcoded, so a third host
joining the map automatically joins the assertion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Repo `ci-deploy.sh` edited after the last push (host lags repo) | RED — sha mismatch reported for web-1/web-2 |
| 2 | `ci-deploy.sh`'s `DEPLOY_SCRIPT_SHA` emit removed | RED — web-2 arm reads absent-marker as non-parity |
| 3 | `cat-deploy-state.sh` `ci_deploy_sha256` field removed | RED — web-1 endpoint arm reads missing field as non-parity |
| 4 | Parity script's per-host loop hardcoded to `[web-1]` only | RED (self-test) — `--self-test` asserts the host set derives from `var.web_hosts`, not a literal |
| 5 | Harness: `--self-test` asserts on a fixture where BOTH arms report the repo sha | PASS — must-PASS input that is not the canonical live path |
| 6 | Add a third `web-3` entry to `var.web_hosts` fixture | RED until a web-3 arm/reading exists — a second-member-after-first row |

### Guard 2 — provisioner-parity guard learns the web-2 sibling class

**Property.** Every SSH `terraform_data` provisioner pins exactly one committed
host key matching the host it dials, and the web-1-pin census stays exact.

**Assembly.** `web-host-provisioner-parity.test.sh` sweeps every `connection`
block in `apps/web-platform/infra/*.tf` (the chokepoint — new provisioners
cannot bypass it) and every destination write vs. the fresh-boot path. The
sibling class rule: a resource whose connection dials `web["web-2"]` must set
`host_key = local.web_2_ssh_host_key`; all others dialing `web["web-1"]` keep
`local.web_1_ssh_host_key`; ALLOWED_HOST_KEYS gains exactly one member. The
same sweep gains a credential-exclusion assertion over the sibling's block
text — no `webhook_doppler_token_env`, `SOLEUR_DOPPLER_TOKEN`, or
`soleur-doppler-token` reference may appear in a `web["web-2"]`-dialing
resource (the #7103 constraint made mechanical).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Sibling edited to `host_key = local.web_1_ssh_host_key` | RED — wrong-host pin |
| 2 | Sibling's `host_key` line deleted | RED — "exactly one host_key" fails |
| 3 | Second `connection` block added to the sibling (or a second web-2 sibling without pin) | RED — per-block census, not totals |
| 4 | FLOOR_RESOURCES left at 18 while the sibling exists | RED — floor proves the census ran over the new member |
| 5 | Harness: mutation battery adds "sibling present but unpinned" and "sibling pinned to web-1 key" rows | both must drive RED — recorded in web-host-provisioner-parity-mutation.test.sh |
| 6 | Sibling gains any reference to `webhook_doppler_token_env` / `SOLEUR_DOPPLER_TOKEN` / the token env-file path | RED — the credential-exclusion is a checked invariant of this resource class, not a review-time convention |

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/server.tf` — `local.web_2_ssh_host_key` (regex/`one()`
  pin reader), `terraform_data.deploy_pipeline_fix_web2` (connection + file +
  remote-exec provisioners, `triggers_replace` multi-input hash covering the
  server id and the pin file).
- `apps/web-platform/infra/outputs.tf` — `output "web_2_server_ip"`.
- `apps/web-platform/infra/web-2-ssh-host-key.pub` — committed pin (new file).
- Providers: unchanged (hcloud, cloudflare, doppler already pinned via
  `.terraform.lock.hcl`). Sensitive variables: `var.ci_ssh_private_key`
  (existing — Doppler `DEPLOY_SSH_PRIVATE_KEY`); no new secret is introduced.

### Apply path

(b) cloud-init + idempotent bootstrap — the sibling IS the bootstrap bridge for
web-2. Owning workflow: `apply-deploy-pipeline-fix.yml` (auto-fires on merge —
`server.tf` and `ci-deploy.sh` are already in its `on.push.paths`). Expected
downtime: none — web-2 is standby; the apply writes files and restarts only
web-2's webhook listener. Blast radius: file writes to web-2 only; web-1
resources unchanged (plan must show zero web-1 deltas — AC).

### Distinctness / drift safeguards

- dev != prd: not applicable — single prd web fleet; the sibling's
  `triggers_replace` includes `hcloud_server.web["web-2"].id` so a replaced
  web-2 re-receives the set.
- `lifecycle.ignore_changes`: NOT added to the sibling (the
  `luks-monitor-install` G2 precedent — a silenced installer is the defect).
- State: terraform.tfstate (R2) gains one `terraform_data` instance; the pin
  value is a public key (non-sensitive).
- Vendor-tier: none (no new betteruptime/monitor resources).

## Architecture Decision (ADR/C4)

Detected: a new cross-component access relationship — CI runner → web-2 root
SSH via the web-1 bastion forward — extending ADR-114's "CI can SSH exactly ONE
host" constraint and adding a second pinned host key under ADR-237.

### ADR

- Amend `ADR-114-one-tunnel-many-connectors-ingress-must-be-origin-relative.md`
  (addendum: the one-SSHable-host constraint is lifted for web-2 by the `-L`
  bastion forward through web-1; origin-relative ingress doctrine unchanged) —
  with a `## Decision` note and `## Alternatives Considered` row for the
  rejected `ssh-web-2.` ingress.
- Touch `ADR-237-ssh-host-keys-are-pinned.md` status context: web-2 joins the
  committed-pin set (`web-2-ssh-host-key.pub`).
- No NEW ADR — the decision is an extension of two existing ones; a standalone
  ADR would split the narrative. (Ordinal collision risk avoided.)

### C4 views

Container diagram, `model.c4`: the `tunnel` container's description ("THREE
ingress rules", connector inventory) stays accurate (no new rule is added) but
the `github -> hetzner` SSH edge description must gain the second hop
(runner→web-1 via `ssh.` bridge → `ssh -L` → web-2:22, both legs host-key
pinned) — enumerate: (a) external actors — none new (GHA runner already an
actor); (b) external systems — none new (Cloudflare Tunnel unchanged, one
tunnel); (c) containers/data-stores — none new (no new store; the web-2 server
element already exists); (d) access relationships — one new: CI→web-2 sshd.
`views.c4`/`spec.c4`: verify the web-2 element renders in the existing
container view; no new element anticipated — confirm at work time and update
edge prose only. `c4-count-parity.test.sh` pinned counts: check whether any
emitter/monitor count changes (none expected — no new emitter, no new monitor).

### Sequencing

The amendment ships with this PR — the decision is true at merge (the route
exists as soon as the apply lands).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] FR1 — `terraform_data.deploy_pipeline_fix_web2` exists in
  `apps/web-platform/infra/server.tf`, `connection.host =
  hcloud_server.web["web-2"].ipv4_address`, `host_key =
  local.web_2_ssh_host_key`, dual-context `private_key`/`agent`, `script_path`
  under `/root/…-%RAND%`, `timeout = "5m"`.
- [ ] FR2 — `apps/web-platform/infra/web-2-ssh-host-key.pub` committed with
  exactly one ECDSA-P256 key line + `#` header (capture method/date/
  fingerprint); `local.web_2_ssh_host_key` reads it through the same
  regex/`one()` fail-closed shape as web-1's; `terraform validate` passes.
- [ ] FR3 — `apply-deploy-pipeline-fix.yml` targets
  `terraform_data.deploy_pipeline_fix_web2` in plan and apply, opens the
  web-1→web-2 `-L` forward + second NAT redirect before plan/apply, and tears
  both down under `if: always()` (tolerant of pre-forward failure).
- [ ] FR4 — the sibling delivers the agreed file set (the 19 non-token FILE_MAP
  members: ci-deploy.sh, ci-deploy-wrapper.sh, webhook.service,
  cat-deploy-state.sh, canary-bundle-claim-check.sh, rendered hooks.json,
  cat-infra-config-state.sh, inngest-enumerate-reminders.sh,
  inngest-rearm-reminders.sh, inngest-wiped-volume-verify.sh,
  cat-inngest-verify-state.sh, inngest-inventory.sh,
  git-lock-chardevice-sweep.sh, inngest-registry-probe.sh,
  inngest-doublefire-probe.sh, and the four 10-*-doppler-token.conf drop-ins —
  plus infra-config-apply.sh, infra-config-install.sh,
  deploy-inngest-bootstrap.sudoers) and asserts each delivered file's on-host
  sha256 against the Terraform-computed hash; `SOLEUR_DOPPLER_TOKEN` /
  `/etc/default/soleur-doppler-token` is NOT delivered.
- [ ] FR5 — `ci-deploy.sh` emits `DEPLOY_SCRIPT_SHA sha256=<sha256 of
  /usr/local/bin/ci-deploy.sh>` once per run, on every host that runs it.
- [ ] FR6 — `cat-deploy-state.sh`'s `/hooks/deploy-status` response includes
  `ci_deploy_sha256` (live sha256 of `/usr/local/bin/ci-deploy.sh`).
- [ ] FR7 — `scripts/check-deploy-script-parity.sh` exits 0 when all
  `var.web_hosts` hosts report the repo sha and non-zero naming the
  divergent/absent host(s) otherwise; `--self-test` prints `ok` with no
  credentials or network.
- [ ] NFR1 — `terraform plan` (canonical invocation: `terraform init
  -input=false` then `doppler run -p soleur -c prd_terraform --name-transformer
  tf-var -- terraform plan` from `apps/web-platform/infra/`, with the two AWS
  `export`s for the R2 backend) shows exactly one create
  (`terraform_data.deploy_pipeline_fix_web2`), zero actions on any
  `hcloud_server`/`hcloud_volume`/other resource.
- [ ] NFR2 — the web-1→web-2 forward authenticates with the existing
  `DEPLOY_SSH_PRIVATE_KEY` through the existing `ssh.` bridge; web-1's host key
  is pinned on the bastion hop (`write-known-hosts.sh` known_hosts), web-2's
  via `connection.host_key`. No TOFU on either hop.
- [ ] NFR3 — all pin/guard tests updated in lockstep:
  `web-host-provisioner-parity.test.sh` (floors 18→19, ALLOWED_HOST_KEYS gains
  `local.web_2_ssh_host_key`, web-2 sibling class), its mutation battery,
  `web-2-host-key-local.test.sh`, `ci-deploy.test.sh`,
  `cat-deploy-state.test.sh`, `scripts/check-deploy-script-parity.test.sh`
  (or `tests/scripts/` twin per suite convention); `terraform-target-parity`
  and `ship-deploy-pipeline-fix-gate` green (edit if the new resource is swept
  by their extractors).
- [ ] NFR4 — no new Cloudflare objects (ingress rules, Access apps/tokens, DNS
  records) and no new Doppler secrets; the full-prd Doppler token is never
  placed on a web-2-bound channel.
- [ ] NFR5 — `apply-web-platform-infra.yml` never plans or applies the sibling
  (no `-target`, no forward): verified by the union test and a comment at the
  resource.
- [ ] NFR6 — `npx markdownlint-cli2` clean on the plan + tasks.md before the
  session summary (sharp edge #8535).
- [ ] Quality gates — touched suites green under `TMPDIR=/data/scratch-9097`;
  `bash -n` clean on every touched `.sh`; actionlint clean on the edited
  workflow (extract embedded `run:` bodies through `bash -c`, never `bash -n`
  the YAML).
- [ ] PR body first line answers "does merging THIS alone mutate production?"
  — YES, and states what the apply writes; body carries `Ref #7103` and
  `Ref #9151` (NOT `Closes` — the post-merge deploy evidence is the closure
  condition, per the ops-remediation convention; #7103 is a tracker and is
  never closed by this PR).

### Post-merge (workflow + telemetry)

- [ ] PM1 — the merge-triggered `apply-deploy-pipeline-fix.yml` run applies
  `deploy_pipeline_fix_web2` green and prints the per-file sha256 assertions.
- [ ] PM2 — `bash scripts/check-deploy-script-parity.sh` (under
  `doppler run -p soleur -c prd_terraform`) exits 0: web-1's
  `/hooks/deploy-status` `ci_deploy_sha256` and web-2's newest
  `DEPLOY_SCRIPT_SHA` row both equal the repo sha.
- [ ] PM3 — a real web deploy (any later merge triggering
  `web-platform-release.yml` or a dispatch) emits `IMAGE_VERIFY: ok` (with the
  `gcr.io` cosign ref) AND `IMAGE_FRESHNESS: ok` from `host_name=soleur-web-2`,
  read back via `scripts/betterstack-query.sh` (decode the double-encoded
  `raw` field before matching) — the #6428/PR #9156 verification the issue
  requests; then `gh issue close 9151`.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the pin file absent/malformed, when `terraform plan` evaluates
  `local.web_2_ssh_host_key`, then it fails closed (regex/`one()`), never
  silently unpinned.
- Given the sibling applied, when `apply-deploy-pipeline-fix.yml` runs, then
  web-2's `/usr/local/bin/ci-deploy.sh` sha256 equals
  `sha256sum apps/web-platform/infra/ci-deploy.sh` at HEAD and the apply log
  names the asserted file set.
- Given `check-deploy-script-parity.sh --self-test`, when run without
  credentials, then it prints `ok` and exits 0.
- Given a tampered delivery (fixture: wrong bytes landed), when the sibling's
  remote-exec asserts, then the apply fails naming the divergent file.
- Given `web-host-provisioner-parity.test.sh`, when the sibling is repointed to
  web-1 or loses its `host_key`, then the guard reds (mutation battery rows).

### Regression Tests

- Given `deploy_pipeline_fix` unchanged, when the workflow plans, then its
  `DPF_REPLACED` sensor and freshness-pin logic behave exactly as before (the
  web-2 sibling does not perturb the web-1 adjudication).
- Given a no-op run (nothing changed), when the workflow finishes, then
  `PLAN_HAS_CHANGES=false` and no auto-close steps fire (existing #7104
  behavior preserved).

### Edge Cases

- web-2 down/unreachable at apply time → the sibling's connection fails loudly
  in the apply (bounded timeout added to the connection block — the
  provisioner-parity guard documents "no `timeout`" today; adding one to the
  NEW resource only keeps a dead web-2 from burning the 90-min budget).
- web-2 replaced between plan and apply → server-id input in
  `triggers_replace` re-fires delivery on the new host; the pin file must be
  re-captured for the new host key (recapture path documented; the apply fails
  closed on key mismatch, never TOFU).
- `DEPLOY_SCRIPT_SHA` absent from old-script deploys → parity script reads
  absence as drift (the stale-marker case is the defect's own signal).
- fail2ban on web-2 bans the web-1 source IP after repeated auth failures →
  the forward step authenticates once, cleanly, with the pinned key; retries
  are bounded and the ban scenario is documented in the risk table.

## Success Metrics

- `apply-deploy-pipeline-fix.yml` run post-merge: web-2 sibling apply green,
  sha assertions printed.
- `check-deploy-script-parity.sh` exits 0 with both hosts at the repo sha.
- Better Stack: `DEPLOY_SCRIPT_SHA` rows from both `host_name`s on the next
  deploy; `IMAGE_FRESHNESS: ok` from `soleur-web-2`.

## Dependencies & Prerequisites

- `var.ci_ssh_private_key`/`DEPLOY_SSH_PRIVATE_KEY` present in Doppler
  `prd_terraform` (existing).
- web-2's root `authorized_keys` carries the CI deploy pubkey (cloud-init
  `ci_ssh_public_key_openssh` — in the templatefile map since before web-2's
  birth; verified).
- web-2's sshd reachable on `10.0.1.11:22` from web-1's connector shell
  (private NIC attached — verified 2026-09-29). `AllowTcpForwarding` on web-1:
  the ADR-220 git-data channel runs `-W 10.0.1.20:22` direct-tcpip through the
  same sshd with the same CI key (C4 records it "Transport LIVE, measured",
  accepted 2026-09-27) — forwarding is proven by live precedent, not just
  config; work-time belt: `sshd -T | grep allowtcpforwarding` via the pinned
  channel, else the `ssh-web-2.` fallback applies.
- `ssh` client on the GHA runner: `ubuntu-latest` ships `openssh-client`
  (used by nothing today — the bridge uses `cloudflared`, not `ssh`; the
  `command -v ssh` check goes in the forward step).
- Local terraform invocation for plan/validate probes uses the canonical
  triplet (per the drift-runbook sharp edge): `export AWS_ACCESS_KEY_ID=
  $(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)` +
  `AWS_SECRET_ACCESS_KEY`, `terraform init -input=false`, `doppler run -p
  soleur -c prd_terraform --name-transformer tf-var -- terraform <plan|validate>`.
- Operator/dev-machine egress in `admin_ips` was needed only to capture the
  pin — already done (2026-09-29); the capture script is also shipped for
  re-keys.

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| R1: `-L` forward unreliable (sshd `AllowTcpForwarding` off on web-1, or forward drops mid-apply) | Pre-check `allowtcpforwarding` at work time; fallback documented (dedicated `ssh-web-2.` ingress + CF Access policy on the existing `ci_ssh` token + CNAME) |
| R2: host-key pin goes stale if web-2 is rebuilt before merge | Recapture via the shipped script; the sibling fails closed on mismatch (never TOFU) — a red apply, not a silent drift |
| R3: parity emit adds a log line a Vector rule drops | `ci-deploy` is already in Source-4's SYSLOG_IDENTIFIER allowlist; `DEPLOY_SCRIPT_SHA` rides the existing tag — verified in vector.toml |
| R4: sibling ordering vs. webhook restart on web-2 | The sibling restarts web-2's webhook after writing hooks.json (SSH path is independent of the listener — same reasoning as `infra_config_handler_bootstrap`); assert `systemctl is-active webhook` post-restart |
| R5: fail2ban on web-2 bans web-1's private IP on auth failures | The forward authenticates once with the pinned key and does not retry-storm; a ban would surface as the sibling's connection failure — loud, diagnosable via the runbook's H4/fail2ban triage |
| R6: TRIGGER_FILES/DPF sweep treats sibling's triggers_replace as deploy_pipeline_fix's | Verify extractor scope at work time; if swept, scope it out deliberately in `ship-deploy-pipeline-fix-gate.test.ts` with a comment — the sibling's file set is the union superset, not the push's |
| R7: sibling's remote-exec renders secrets into argv | Deliver `hooks.json` via base64 remote-exec exactly as `infra_config_handler_bootstrap` does (sensitive interpolation is permitted in remote-exec but never in `command`/argv or `file` sources — reuse that block's mechanism verbatim) |
| R8: second `-target=` transitive pulls (hcloud_server.web["web-2"] enters the plan graph) | The shared destroy-guard filter counts host creates — a `create` would halt; verify plan shows zero host actions (the sibling references the existing instance, not a create) |

## Resource Requirements

Single PR; engineering-infra scope. Prod-touching via the sanctioned apply
workflow only — no operator SSH, no dashboard steps.

## Future Considerations

- #7103 B4 generalizes this sibling to the full 19-installer fleet when the
  cattle model extends; this PR proves the web-2 route + pin pattern those
  installers will reuse.
- `deploy-web-2.`/`ssh-web-2.` dedicated ingress remains available if the
  bastion forward proves fragile under load (recorded as the fallback).
- The full-prd Doppler token's re-delivery to web-2 stays #7103-B4 scope — the
  sibling deliberately does not carry it.
- The `DEPLOY_SCRIPT_SHA` field can later feed a scheduled drift check (the
  daily stale-image/staleness alerting items in #7103 B3).

## Documentation Plan

- ADR-114 addendum + ADR-237 context touch-up (Architecture Decision section).
- `model.c4` tunnel/edge description updates (Architecture Decision section).
- Runbook pointer: `knowledge-base/engineering/operations/runbooks/` — add or
  amend the SSH/host-key triage note to name `web-2-ssh-host-key.pub` +
  `scripts/capture-web-host-key.sh` (pick the file at work time to match the
  capture-script shape).
- PR body must carry `Ref #7103` (tracker — never closed by this PR) and
  `Ref #9151`; issue closure happens post-merge after PM3 evidence, per the
  ops-remediation convention (`Closes` auto-closes at merge, before the
  confirming deploy telemetry exists).

## References & Research

### Internal References

- `apps/web-platform/infra/server.tf` — `deploy_pipeline_fix` (local-exec),
  `infra_config_handler_bootstrap` (SSH bridge shape), `local.web_1_ssh_host_key`
  pin reader, `docker_seccomp_config` (server-id-in-triggers fresh-host pattern)
- `apps/web-platform/infra/tunnel.tf` — ingress rules + CF Access apps/tokens
- `apps/web-platform/infra/dns.tf` — `cloudflare_record.{deploy,ssh,registry}`
- `apps/web-platform/infra/ci-deploy.sh` — `fan_out_to_peers`, `write_state`,
  `IMAGE_VERIFY`/`IMAGE_FRESHNESS` emit functions
- `apps/web-platform/infra/infra-config-apply.sh` — `FILE_MAP` (20 entries) +
  per-file sha256 state frame
- `.github/actions/cf-tunnel-ssh-bridge/` — bridge mechanics + teardown
  contract + `write-known-hosts.sh` pin writer
- `apps/web-platform/infra/web-host-provisioner-parity.test.sh` — the census
  guard that must learn the sibling class
- `apps/web-platform/infra/web-1-host-key-local.test.sh` — pin-shape test model
- `scripts/capture-web-1-host-key.sh` — capture contract
- `scripts/betterstack-query.sh` — ClickHouse query path for per-host rows
- ADR-068, ADR-114, ADR-143, ADR-220, ADR-237 — governing decisions

### Related Work

- #9151 (this issue), #7103 (tracker; B4 pre-decides the shape — `Ref`, not
  `Closes`), #6428 + PR #9156 (IMAGE_FRESHNESS origin of the verification ask),
  #7095/PR-A (credential re-delivery precedent), #4804/#4811 (handler
  chicken-and-egg), #6594 (false-green apply; why sha asserts are in-band),
  #7226 (host-key pinning), #8706 (script_path secret-residue rule)

## Consult & Review Provenance

- **Plan-skill advisor consult (Phase 4.5):** not run — this harness exposes no
  `advisor`/Task-subagent tool and no advisor-capable MCP server (checked:
  stripe, context7, playwright, cloudflare, vercel). Recorded so `plan-review`
  knows the consult was deliberately absent, not skipped silently. The plan is
  not trivially mechanical, so `plan-review`'s panel and `deepen-plan` carry
  extra weight here.
- **Domain agents:** assessed inline (Domain Review) for the same reason.
- **Functional-overlap / community-discovery fan-outs:** assessed inline; no
  uncovered stack and no overlapping in-flight PR surface found (open
  code-review overlap check: only #2197's hypothetical server.tf mention).
