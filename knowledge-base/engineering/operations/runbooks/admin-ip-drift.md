---
category: infrastructure
tags: [ssh, firewall, hetzner, admin-ip, drift, recovery]
date: 2026-04-19
---

# Admin IP Drift -- Recovery Runbook

**Issue:** #2681
**Servers:** web-platform CX33 (`soleur-web-platform`, `135.181.45.178`)
**Related runbook:** `ssh-fail2ban-unban.md` (for sshd-layer lockouts)
**Automation:** `/soleur:admin-ip-refresh`

## Symptom

Operator SSH to `soleur-web-platform` hangs or resets, AND the server-side
`journalctl -u ssh` shows NO entry for the operator IP within the relevant
time window. This distinguishes admin-IP drift from the fail2ban lockout
class documented in `ssh-fail2ban-unban.md`.

```text
$ ssh root@135.181.45.178 'hostname'
kex_exchange_identification: read: Connection reset by peer
```

If the reset is accompanied by sshd journal entries for the operator IP
(login attempts, banner exchange, auth failures), this is NOT admin-IP
drift -- jump to `ssh-fail2ban-unban.md`. The absence of journal entries
is the load-bearing signal for this runbook: the packet never reached
sshd because the Hetzner Cloud Firewall dropped it at the `var.admin_ips`
allow-list.

## Root Cause

`apps/web-platform/infra/firewall.tf` scopes port-22 ingress to the CIDRs
in `var.admin_ips`, hydrated from `Doppler prd_terraform/ADMIN_IPS` at
apply time. When the operator's ISP-assigned egress IP rotates (router
reboot, NAT remapping, travel to a different network) and `ADMIN_IPS`
has not been refreshed, the new packet is dropped by the firewall. sshd
never sees the SYN.

The originating incident (2026-04-19) had `ADMIN_IPS=["82.67.29.121/32"]`
(a single-entry list) and the operator's current egress was
`66.234.146.82`. No margin, silent drop.

## Diagnosis

Run these in order BEFORE blaming sshd or fail2ban. L3 (firewall) must
be cleared before any L7 (sshd, fail2ban) hypothesis is considered. This
ordering is enforced by AGENTS.md `hr-ssh-diagnosis-verify-firewall`.

### Step 1 -- Get current egress IP (from the operator machine)

```bash
curl -s --connect-timeout 5 --max-time 10 https://ifconfig.me/ip
# Fallback if the above returns nothing:
curl -s --connect-timeout 5 --max-time 10 https://api.ipify.org
# Last-resort fallback:
curl -s --connect-timeout 5 --max-time 10 https://icanhazip.com
```

Validate the response matches an IPv4 dotted quad. HTML/empty responses
indicate an upstream-routing anomaly in that provider -- try the next.

### Step 2 -- Get current `ADMIN_IPS` from Doppler (source of truth)

```bash
doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain
```

Requires Doppler CLI auth. The output is a JSON list of `/32` CIDRs.

### Step 3 -- Get current firewall rule from Hetzner (realized state)

```bash
hcloud firewall describe soleur-web-platform
```

Look for the port-22 rule's `source_ips` list. This should match
`ADMIN_IPS` verbatim after every successful `terraform apply`.

### Step 4 -- Diff

Two invariants to check:

- Is `<current-egress>/32` in the Doppler `ADMIN_IPS` list?
- Is the Doppler `ADMIN_IPS` list identical to the Hetzner firewall's
  source_ips list?

If EITHER is false, you have admin-IP drift. Proceed to Recovery.

If BOTH are true AND SSH still resets, drift is NOT the cause. Fall
through to `ssh-fail2ban-unban.md` (sshd-layer diagnosis).

## Recovery (Automated)

Run `/soleur:admin-ip-refresh` and follow its prompts. The skill:

1. Detects current egress IP with three-service fallback validation.
2. Reads `ADMIN_IPS` from Doppler and diffs against the egress IP.
3. Warns on single-entry lists (the risk class that caused the original
   incident) and on lists with more than 10 entries (stale residue).
4. Shows the exact Doppler mutation (pre-image and post-image) and waits
   for explicit operator go-ahead -- no `--yes`, no auto-approve, per
   AGENTS.md `hr-menu-option-ack-not-prod-write-auth`.
5. On approval, writes Doppler (stdin-piped, `--silent`) and prints the
   Doppler dashboard activity URL for the audit trail.
6. Emits the exact `terraform plan` and `terraform apply` invocations
   (both full-graph and `-target=hcloud_firewall.web` forms) for the
   operator to run. The skill does NOT call Terraform itself -- per
   AGENTS.md `hr-all-infrastructure-provisioning-servers`, Terraform
   apply is an operator-initiated action.

## Recovery (Manual Fallback)

If `/soleur:admin-ip-refresh` is unavailable:

### Step R1 -- Add the current egress CIDR to Doppler `ADMIN_IPS`

Never widen the firewall to `0.0.0.0/0` as a "quick fix". Instead,
append the new CIDR to the existing list using `jq` so the JSON shape
is validated and no placeholder can survive a copy-paste:

```bash
# Capture current list (JSON) and current egress IP:
CURRENT=$(doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain)
EGRESS=$(curl -s --connect-timeout 5 --max-time 10 https://ifconfig.me/ip)

# Sanity-check the egress matches an IPv4 before trusting it:
[[ "$EGRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
  || { echo "bad egress: $EGRESS"; exit 1; }

# Compose the new list (current + new /32) via jq. Reject if CURRENT
# isn't valid JSON or jq produces nothing:
NEW=$(printf '%s' "$CURRENT" | jq -c --arg ip "$EGRESS/32" '. + [$ip]') \
  || { echo "jq compose failed"; exit 1; }

# Write to a unique 0600 temp file; trap ensures scrub on exit.
# Do NOT pass values on the command line (would leak via `ps auxf`).
umask 077
TMP=$(mktemp -t admin-ips.XXXXXX)
trap 'shred -u "$TMP" 2>/dev/null || rm -f "$TMP"' EXIT
printf '%s\n' "$NEW" > "$TMP"

# Review the composed list (optional):
cat "$TMP"

# Write (--silent prevents value echo into captured stdout):
doppler secrets set ADMIN_IPS -p soleur -c prd_terraform --silent < "$TMP"
```

### Step R2 -- Apply the Terraform change

```bash
cd apps/web-platform/infra

# Plan first -- review diff before apply:
doppler run --project soleur --config prd_terraform \
  --name-transformer tf-var -- \
  terraform plan -target=hcloud_firewall.web

# Apply -- confirms at Terraform's native prompt (no --auto-approve):
doppler run --project soleur --config prd_terraform \
  --name-transformer tf-var -- \
  terraform apply -target=hcloud_firewall.web
```

`-target=hcloud_firewall.web` is the recovery-scoped form -- it skips the
dependency graph. Safe here because the change is confined to a single
firewall resource, but run a full `terraform plan` in a follow-up to
confirm no drift elsewhere.

### Step R3 -- Verify

```bash
# Operator machine:
ssh -vvv root@135.181.45.178 'hostname'

# From operator with Hetzner CLI auth:
hcloud firewall describe soleur-web-platform | grep -A1 'port: "22"'
```

SSH should succeed on first try. The firewall rule's source_ips should
include the new CIDR.

## Prevention

`/soleur:admin-ip-refresh` is designed to run pre-emptively. Operators
should run it whenever they notice their IP may have rotated (router
reboot, travel to a new network), not only after an outage.

Single-entry `ADMIN_IPS` lists are the root risk -- no rotation margin.
The skill warns on this and asks for explicit acknowledgment. A
recommended steady state is 2-3 known-good CIDRs (home WAN + mobile
hotspot + one travel/coworking).

## Sharp Edges

- **VPN / Cloudflare WARP:** `ifconfig.me` returns the egress IP as the
  internet sees the operator -- which is the VPN egress when one is
  active. That IS the IP the Hetzner firewall will see, so adding the
  VPN egress to `ADMIN_IPS` is correct. Do not attempt to detect the
  "real" home IP behind the VPN.
- **Stale entries accumulate:** Each drift event appends a new CIDR.
  Review `ADMIN_IPS` quarterly and prune CIDRs no longer in use. The
  skill emits a P2 warning when the list exceeds 10 entries.
- **Doppler write succeeds but `terraform apply` forgotten:** A silent
  drift the other direction -- Doppler has the new CIDR but the firewall
  does not. The skill explicitly prompts for `terraform apply` and
  refuses to mark itself "done" until the operator confirms they ran
  it. A scheduled daily drift check (deferred, tracked separately)
  catches this class within 24 hours.
- **Audit trail:** Doppler logs every secret mutation by token identity.
  The activity URL is
  `https://dashboard.doppler.com/workplace/projects/soleur/configs/prd_terraform/activity`
  -- useful for post-incident "who added this CIDR, and when?".

## Do NOT

- Do NOT widen `hcloud_firewall.web` port-22 rule to `0.0.0.0/0`. That
  regresses defense-in-depth and amplifies fail2ban exposure; every
  scanner on the internet would be hammering sshd.
- Do NOT pass `-auto-approve` or `--yes` to `terraform apply` or to
  `doppler secrets set` in the `prd_terraform` config. Per AGENTS.md
  `hr-menu-option-ack-not-prod-write-auth`, destructive writes against
  shared prod require per-command go-ahead.
- Do NOT SSH into the host to "fix" the firewall live. The firewall
  lives in Terraform; changes go through `terraform apply`, not
  `iptables`/`nftables` edits on the host. Per AGENTS.md
  `hr-all-infrastructure-provisioning-servers`, SSH is read-only
  diagnosis.
- Do NOT store CIDRs with timestamps in `ADMIN_IPS` as JSON objects --
  Doppler's flat-secret model doesn't support it natively. If operator
  turnover or age-out becomes a maintenance burden, plan a migration to
  Cloudflare Access for SSH (identity-bound) rather than bolting a
  side-channel onto `ADMIN_IPS`.

## Related

- Automation skill: `plugins/soleur/skills/admin-ip-refresh/SKILL.md`
- Plan: `knowledge-base/project/plans/2026-04-19-ops-admin-ip-drift-prevention-plan.md`
- Sibling runbook: `ssh-fail2ban-unban.md` (sshd-layer lockout class)
- Institutional learning:
  `knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
  (same root class, CI angle -- firewall-layer drift mistaken for auth
  failure)
- AGENTS.md rules: `hr-ssh-diagnosis-verify-firewall`,
  `hr-all-infrastructure-provisioning-servers`,
  `hr-menu-option-ack-not-prod-write-auth`.

## Verification of CLI tokens used here

Per AGENTS.md `cq-docs-cli-verification`:

- `curl -s https://ifconfig.me/ip` -- <!-- verified: 2026-04-19 source: https://ifconfig.me -->
- `curl -s https://api.ipify.org` -- <!-- verified: 2026-04-19 source: https://www.ipify.org/ -->
- `curl -s https://icanhazip.com` -- <!-- verified: 2026-04-19 source: https://major.io/p/icanhazip-com-faq/ -->
- `doppler secrets get <KEY> -p <proj> -c <config> --plain` -- <!-- verified: 2026-04-19 source: https://docs.doppler.com/docs/accessing-secrets -->
- `doppler secrets set <KEY> -p <proj> -c <config> --silent` -- <!-- verified: 2026-04-19 source: https://docs.doppler.com/docs/setting-secrets -->
- `hcloud firewall describe <name>` -- <!-- verified: 2026-04-19 source: hcloud firewall describe --help -->
- `terraform plan -target=<addr>` -- <!-- verified: 2026-04-19 source: https://developer.hashicorp.com/terraform/cli/commands/plan#target-address -->
- `terraform apply -target=<addr>` -- <!-- verified: 2026-04-19 source: https://developer.hashicorp.com/terraform/cli/commands/apply#target-address -->
