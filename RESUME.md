# Resume: fan the 15 web-1-pinned host provisioners out over `var.web_hosts`

**Issue:** #7000 (OPEN — use `Closes #7000`; this PR fully resolves it)
**Branch:** `feat-fix-7000-web-host-provisioner-foreach`
**Worktree:** `.worktrees/feat-fix-7000-web-host-provisioner-foreach/`
**Base:** `main` @ `655eb012c`

Everything below was **measured**, not recalled, on 2026-07-27 at that SHA.

---

## The task in one line

`apps/web-platform/infra/server.tf` has 16 `terraform_data` host-provisioning resources. **15 hardcode `connection.host = hcloud_server.web["web-1"].ipv4_address`; exactly 1 is `for_each`'d over `var.web_hosts`.** So `soleur-web-2` boots but never receives per-host env files, unit enablement, or config.

Verify the split is still true before starting (it can drift):

```bash
grep -c 'host        = hcloud_server.web\["web-1"\].ipv4_address' apps/web-platform/infra/server.tf   # expect 15
grep -c 'for_each = var.web_hosts' apps/web-platform/infra/server.tf                                  # expect 1
```

The 15: `disk_monitor_install`, `resource_monitor_install`, `container_restart_monitor_install`,
`private_nic_guard_install`, `zot_consumer_probe_install`, `git_data_probe_install`, `fail2ban_tuning`,
`journald_persistent`, `cosign_trusted_root`, `registry_insecure_config`, `infra_config_handler_bootstrap`,
`docker_seccomp_config`, `apparmor_bwrap_profile`, `orphan_reaper_install`, `cron_egress_firewall`.

---

## THE trap — read this before writing any terraform

Converting a singular resource to `for_each` **changes its address**: `terraform_data.X` → `terraform_data.X["web-1"]`. Terraform reads that as **destroy + create** unless a `moved` block is supplied. For `terraform_data` with `provisioner` blocks, a recreate **re-runs every provisioner against live web-1** — and for members like `cron_egress_firewall` and `docker_seccomp_config` that is not a no-op.

**Copy the precedent exactly:** `apps/web-platform/infra/placement-group.tf:23-40` already performs this migration for four resources, each with a `moved` block. `hcloud_volume.workspaces` carries the note *"the `moved` migration below is 0-destroy"*.

The `for_each` shape to mirror is at `server.tf:1628` (`hcloud_volume.workspaces`), which keys off `var.web_hosts` and special-cases web-1's legacy name:

```hcl
for_each = var.web_hosts
name     = each.key == "web-1" ? "soleur-web-platform-data" : "soleur-web-platform-data-${each.key}"
```

`var.web_hosts` is `map(object({ location, private_ip, server_type }))` (`variables.tf`), so `each.value.private_ip` is available — but the current provisioners connect over the **public** `ipv4_address`, so check which address each one needs before switching.

**Acceptance is a plan, not a test.** No suite can distinguish a correct `moved` set from a missing one:

```bash
cd apps/web-platform/infra
doppler run -p soleur -c prd_terraform -- terraform plan
# REQUIRED: 0 destroys, 0 replacements of existing web-1 resources.
```

---

## Second trap — this change is currently unguarded

```bash
git grep 'terraform_data' -- '*.test.sh' '*.test.ts'   # returns NOTHING
```

No suite asserts on any of these resources by name. A wrong `for_each`, a missing `moved`, or a provisioner silently dropped from the fleet all ship green today. **A guard is part of this work, not a follow-up.**

Suggested shape (mirrors the existing per-unit drift guards, e.g. `web-private-nic-guard.test.sh`): every `terraform_data` in `server.tf` with an SSH `connection` block must either be `for_each`'d over `var.web_hosts`, or appear in an explicit allowlist with a stated reason. Include a **non-vacuity floor** (`>= 15` resources swept) so a broken extraction fails loudly rather than reporting a clean sweep of nothing, and **mutation-prove it** (delete a `for_each`, confirm red).

---

## Classify before fanning out

Not all 15 are fleet-wide. Decide per resource and record the reason:

- `infra_config_handler_bootstrap` — the deploy-webhook SSH bridge. Plausibly **web-1-only by design**; check `ci-deploy.sh` / `hooks.json.tmpl` before fanning it out.
- `registry_insecure_config`, `cosign_trusted_root` — may be singleton or fleet-wide; read what consumes them.
- `git_data_probe_install` — **definitely fleet-wide** (it is the reason #7000 exists; it writes `/etc/default/web-git-data-probe` and enables the timer).

The guard's allowlist is where a justified web-1-only exception lives.

---

## Gates — every path below was verified to exist and run at `655eb012c`

**Run from the worktree, never the repo root** — the root is a *bare* repo and `run-registered-suites.sh` dies there with `fatal: this operation must be run in a work tree`.

| command | baseline at `655eb012c` |
|---|---|
| `bash apps/web-platform/infra/run-registered-suites.sh` | **72 passed, 0 failed (of 72)** |
| `bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra` | **rendered+validated 7/7** |
| `(cd apps/web-platform/infra && terraform fmt -check -recursive)` | **clean** |
| `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` | **30 pass** |
| `bash scripts/test-all.sh` | run before ship; it covers what the infra suites structurally do not |

Note `run-registered-suites.sh` has been observed reporting `71/72` under `-P 6` and `72/72` on re-run against an unchanged tree — parallel contention, not a regression. Re-run before treating it as a failure.

---

## Constraints that will bite

1. **`cloud-init.yml` has 72 bytes of headroom** — it renders to **23,628 B** against a **23,700 B** budget (`plugins/soleur/test/cloud-init-user-data-size.test.ts`). If this work touches cloud-init *at all*, it trips the gate. Widening the budget is a separate two-line PR; do that first rather than trimming prose under pressure.
   **Measure with the test, never a hand-rolled `gzip`** — the file is a terraform *template* the test renders first, so `gzip -9 | base64 | wc -c` on the source reads ~390 B **low** and will tell you you are under budget when you are not.
2. **`orphan-reaper.test.sh` is NOT registered** — it is one of 9 suites `run-registered-suites.sh` reports as referenced by no workflow or script. If this work touches `orphan_reaper_install`, register the suite or its coverage is decorative.
3. **Doppler env is baked at container start** (`--env-file` in cloud-init). Flipping a Doppler value does not reach a running container; a redeploy is required.

---

## Verification that the fix actually worked

Do not stop at a green plan. Confirm web-2 receives a previously-web-1-only artifact, read **off-host** (`hr-no-ssh-fallback-in-runbooks`):

- web-2 is `soleur-web-2`, id `155786558`, private `10.0.1.11`, public `204.168.189.200`.
- The cheapest positive signal is the git-data probe heartbeat, but note `betteruptime_heartbeat.git_data_prd` is `paused = true` and the git-data host **does not exist yet** — so pick an artifact whose consumer is live today (e.g. `disk_monitor` or `container_restart_monitor` telemetry in Sentry/Better Stack, host-scoped to `soleur-web-2`).

---

## Context you will want

- **web-2 booted clean for the first time on 2026-07-27** (#6969, closed). It is a healthy **warm standby serving no traffic** — the apex A record points at web-1 (`dns.tf`) and web-2 was de-pooled from the shared Cloudflare Tunnel (#6425). "Booted clean" is the bar; "serving requests" is not.
- **git-data is not provisioned.** No `soleur-git-data` in Hetzner; planned at `10.0.1.20`. `GIT_DATA_SSH_HOST`, `GIT_DATA_STORE_ENABLED`, `GIT_DATA_TRANSPORT_KEY`, `GIT_DATA_HEARTBEAT_URL` are all **absent from Doppler `prd`**. This work is a *precondition* for git-data on web-2, not a dependency of it — do not couple them.
- **Network + auth to git-data need no per-host change.** Hetzner firewalls do not filter the private net (stated at `server/session-proxy.ts:207`), and git-data authorizes by forced-command **key**, not by IP (`cloud-init-git-data.yml:55-59`). Contrast `inngest-host.tf:55`, which *does* hardcode `web_host_private_ips = "10.0.1.10,10.0.1.11"`.
- **Unverified, worth checking:** `resolveGitDataSshHost()` (`server/git-data-replication.ts:58`) **throws** in production when `GIT_DATA_SSH_HOST` is unset. The store is documented as a fail-soft overlay, so presumably the caller catches — I did not trace it. If it does not, populating that secret before git-data is reachable is a live hazard on **web-1** too.

---

## Related open work

- **#6985** — `runcmd` sources the Doppler env file with a bare `.` at the sites above the `set -a`, so ~10 non-fatal call sites get no token. CONCUR-gated scope-out; re-evaluate now that #6969 is closed.
- **`Scheduled: Cron Artifact Age`** — red daily since at least 2026-07-22, all 9 cron producers reporting `NEVER`. Pre-existing, systemic, **untracked**. Not this work, but nothing is watching it.
