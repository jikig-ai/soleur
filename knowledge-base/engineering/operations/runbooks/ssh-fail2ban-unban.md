---
category: infrastructure
tags: [ssh, fail2ban, security, recovery, hetzner]
date: 2026-04-19
---

# SSH Locked Out by fail2ban -- Recovery Runbook

**Issue:** #2654
**Servers:** web-platform CX33 (`soleur-web-platform`, `135.181.45.178`)
**Channel of last resort:** Hetzner Cloud Console (noVNC in-browser)
**See also:** `admin-ip-drift.md` -- firewall-layer lockout class where the
operator's egress IP has rotated out of `ADMIN_IPS`. If `journalctl -u ssh`
shows NO entry for the operator IP during the incident window, the packet
never reached sshd and this runbook does not apply -- check admin-IP drift
first.

## Symptom

From the operator machine:

<!-- lint-infra-ignore start: pasted failure transcript, not a prescribed step. This is the reader's entry-point discriminator that routes between this runbook and admin-ip-drift.md; it cannot be renamed or moved. Class (b-transcript), owner #7874. -->
```text
$ ssh root@135.181.45.178 'hostname'
kex_exchange_identification: read: Connection reset by peer
Connection reset by 135.181.45.178 port 22
```
<!-- lint-infra-ignore end -->

Reset happens at the kex banner phase (before any auth). The host is
otherwise reachable: `hcloud server list` shows `running`, HTTPS 200 on
`app.soleur.ai` and `soleur.ai`. The firewall already scopes port 22 to
`var.admin_ips`, so TCP reaches sshd -- the reset is fail2ban at the
`nftables` layer.

## Root Cause (Most Common)

`sshd_config.d/01-hardening.conf` enforces `AllowUsers root`. A single
`ssh <non-root-user>@<ip>` attempt (e.g., `ssh deploy@...`) produces a
rejected connection per try; 5 rejects within 10 min trip the `[sshd]`
jail. With `bantime.increment = true` and no `bantime.maxtime` cap, the
ban escalates as `bantime * factor^count`: 10m, 20m, 40m, 80m, 160m, ...
Without the cap, a handful of mistakes during one incident can produce a
multi-hour or multi-day lockout.

After PR #2654 ships, the Terraform drop-in pins
`bantime.maxtime = 1h`, so the worst case is a 1-hour ban. Before that
lands (or if recidive history is already escalated past the cap), use
this runbook.

## Recovery Procedure

The channel we need to automate (SSH) is the channel that is down --
this is the one operator task where the Hetzner Cloud Console (noVNC) is
the only tool.

### Step 1: Open the Cloud Console

1. Go to <https://console.hetzner.cloud/>.
2. Select the `soleur` project.
3. Click `soleur-web-platform` in the server list.
4. Click the **Console** tab (opens an in-browser noVNC session,
   pre-authenticated to the project).
5. Log in as `root` at the console prompt.

### Step 2: Confirm the fail2ban version

`bantime.maxtime` and the `AllowUsers` filter match both require
fail2ban >= 0.11. Ubuntu 24.04 ships 1.0.2 -- capture the actual value
for the incident log:

```bash
fail2ban-client --version
```

### Step 3: Capture ban state before clearing

Record this before unbanning so the post-incident review has a full
trace:

```bash
fail2ban-client status sshd
journalctl -u ssh --since "1 hour ago" --no-pager | head -200
```

### Step 4: Unban

Preferred -- unban a specific IP when it is known:

```bash
fail2ban-client set sshd unbanip 82.67.29.121
```

Fallback -- unban all IPs across all jails. Safe because `[sshd]` is
the only active jail on this host, and during an SSH-lockout incident
in-band recovery matters more than precise audit trails. The pre-unban
`status sshd` capture from Step 3 preserves the ban list:

```bash
fail2ban-client unban --all
```

If the operator's IP has rotated via NAT and the new prefix is unknown,
use the fallback.

**Caveat:** `unban --all` also releases any attacker IPs banned in the
same moment. Prefer `unbanip <ip>` when the operator IP is known. If a
brute-force attack is in progress, the attacker will be re-banned within
one `findtime` window (10 min) on the next `maxretry` rejected tries --
acceptable exposure given `PasswordAuthentication no` + `AllowUsers root`
means no attempt can succeed without a stolen key.

### Step 5: Verify sshd health

```bash
systemctl status ssh --no-pager
journalctl -u ssh -n 50 --no-pager
```

Look for active/running, no recent `Failed to load key` or crash
restarts.

### Last-resort diagnosis (SSH channel -- not the noVNC channel of last resort) -- Step 6: confirm SSH is restored

This is the terminal verification of the recovery above, not an entry point --
do not start here. Reach it only after Steps 1-5 have run.

**Say what is true about the preceding steps: they are noVNC console commands,
not no-SSH probes.** Steps 1-5 run inside a Hetzner Cloud Console session --
that is a different LOGIN CHANNEL, not an off-host read path. This runbook
prescribes no off-host read before this point, and that is a gap rather than a
design.

**Probe before you authenticate.** An L4 banner probe
(`bash -c '</dev/tcp/<ip>/22'`, or `nc -z -w5 <ip> 22`) opens TCP and reads the
SSH banner without offering credentials. It tells you whether the unban took --
a reset at the banner means the jail is still active, an `SSH-2.0-OpenSSH_...`
banner means it cleared -- and it is the same class of off-host read as
`curl ifconfig.me` in the sibling runbook.

**This matters for safety, not just for rule compliance.** `## Root Cause`
records `maxretry` rejections inside one `findtime` window tripping the `[sshd]`
jail, with `bantime.increment = true` and no `bantime.maxtime` cap. A failed
`ssh` attempt **feeds that counter**. If the unban did not take -- wrong IP, or
the recidive jail already escalated -- retrying `ssh` here RE-ARMS the ban the
operator just cleared, at a longer bantime, quite possibly after the noVNC tab
is closed. The banner probe does not authenticate and does not feed the jail.

So: probe first, attempt `ssh` **once**, and if it fails do NOT retry -- re-open
the noVNC console and go to `## If This Runbook Does Not Work`. What the `ssh`
attempt adds over the banner probe is confirmation of end-to-end key
authentication, which no off-host read can give; that is the narrow ground on
which it is sanctioned under `hr-no-ssh-fallback-in-runbooks`.

**Observability layer:** L4 banner probe (operator machine) + the noVNC console.
Layers 1-6 do NOT cover this: `apps/web-platform/infra/vector.toml` Source 2
(`system_journald`) ships `PRIORITY 0-2` only and Source 4 carries no `sshd` or
`fail2ban` tag, so the sshd-journal signal this runbook routes on is readable
only from the host console. Widening that filter is a log-quota decision, not a
free win -- tracked rather than assumed.

**"Last resort" here names the SSH _probe_, not the recovery _channel_.** This
runbook's channel of last resort is the Hetzner Cloud Console (noVNC) named in
the header, and its premise is that SSH is down. If this step fails, the
escalation path is `## If This Runbook Does Not Work` -- not another SSH attempt.

Back on the operator laptop:

```bash
# 1. No authentication -- does the channel answer? Reads the banner only, and
#    CANNOT feed the fail2ban maxretry counter.
#    reset/timeout = still banned; SSH-2.0-OpenSSH_... = the unban took.
timeout 5 bash -c 'cat </dev/tcp/135.181.45.178/22' | head -1

# 2. ONE attempt, only if the banner came back. Confirms end-to-end key auth.
#    If this fails, do NOT retry -- each failure feeds maxretry and can re-arm
#    the ban at a longer bantime. Re-open noVNC and see
#    `## If This Runbook Does Not Work`.
ssh -vvv root@135.181.45.178 'hostname'
```

Should succeed on first try.

## Capture for the PR / Incident Record

Paste the following on a PR comment or incident ticket for the next
responder:

- `fail2ban-client --version` output.
- `fail2ban-client status sshd` output from Step 3 (pre-unban state).
- `fail2ban-client get sshd bantime`, `get sshd maxretry`,
  `get sshd findtime`, `get sshd journalmatch` -- documents the
  effective config at incident time.
- Line from `journalctl -u ssh` that triggered the initial ban
  (usually `User <x> not allowed because not listed in AllowUsers` or
  `Invalid user <x>`).

## Do NOT

- Do not add `ignoreip = <operator IP>` to the jail config. Operator
  IPs are NAT-dynamic; an `ignoreip` rule becomes a stale whitelist the
  moment the ISP rotates the prefix.
- Do not set `bantime = -1` (permanent ban). Locks out the same
  operator who typoed once; only recoverable via this runbook.
- Do not SSH into the host to "fix" the jail config live -- the fix
  ships through Terraform: see
  `apps/web-platform/infra/fail2ban-sshd.local` and
  `terraform_data.fail2ban_tuning` in `server.tf`. Per AGENTS.md
  `hr-all-infrastructure-provisioning-servers`, SSH is for read-only
  diagnosis.
- Do not widen firewall port 22 to `0.0.0.0/0` to "bypass" the jail.
  The firewall is correctly scoped to `var.admin_ips`; widening it
  regresses hardening. If the operator IP is wrong, update
  `var.admin_ips` in the `prd_terraform` Doppler config and re-apply.

## If This Runbook Does Not Work

If `fail2ban-client status sshd` shows no bans but SSH still resets at
kex, the root cause is not fail2ban. Diagnose in this order:

1. `systemctl status ssh` -- sshd crashed or failed to start after a
   config change. Fix: revert the sshd config and restart.
2. `free -h` / `systemctl status` -- OOM killed sshd. Fix: free memory
   (`docker container prune`, etc.) then restart sshd.
3. `cat /etc/hosts.deny` -- legacy hardening added a block.
4. `nft list ruleset | grep -i drop` -- an adjacent hardening layer
   (e.g., sshguard) dropped the IP. fail2ban uses nftables on this
   host, so bans appear here too.

## Related

- Plan: `knowledge-base/project/plans/2026-04-19-fix-prod-ssh-kex-reset-plan.md`.
- Prior plan (installed fail2ban):
  `knowledge-base/project/plans/2026-03-19-security-add-fail2ban-ssh-protection-plan.md`.
- AGENTS.md rules: `hr-all-infrastructure-provisioning-servers`,
  `hr-never-label-any-step-as-manual-without`,
  `cq-for-production-debugging-use`.

## Verification of CLI tokens used here

Per AGENTS.md `cq-docs-cli-verification`:

- `fail2ban-client status sshd` -- <!-- verified: 2026-04-19 source: https://github.com/fail2ban/fail2ban/blob/1.0.2/man/fail2ban-client.1 -->
- `fail2ban-client set sshd unbanip <ip>` -- <!-- verified: 2026-04-19 source: https://github.com/fail2ban/fail2ban/blob/1.0.2/man/fail2ban-client.1 -->
- `fail2ban-client unban --all` -- <!-- verified: 2026-04-19 source: https://github.com/fail2ban/fail2ban/blob/1.0.2/client/fail2banclient.py -->
- `fail2ban-client get sshd <key>` (bantime, maxretry, findtime, journalmatch) -- <!-- verified: 2026-04-19 source: https://github.com/fail2ban/fail2ban/blob/1.0.2/man/fail2ban-client.1 -->
- `fail2ban-client --version` -- <!-- verified: 2026-04-19 source: fail2ban-client --help -->
