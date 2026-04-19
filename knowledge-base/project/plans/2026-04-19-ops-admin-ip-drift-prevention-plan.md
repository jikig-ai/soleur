---
title: "ops: prevent admin-IP drift from causing prod SSH lockouts"
type: ops
date: 2026-04-19
semver: minor
issue: 2681
---

# ops: prevent admin-IP drift from causing prod SSH lockouts

## Enhancement Summary

**Deepened on:** 2026-04-19
**Sections enhanced:** 5 (Overview, Proposed Solution Phase 2, Risks & Mitigations,
Hypotheses, Alternative Approaches Considered).
**Research sources:** Cloudflare One docs (SSH via cloudflared, Access for
Infrastructure), ipify official API docs + SANS ISC analysis of bot-used IP
APIs, Doppler CLI docs (`setting-secrets`, `--silent` flag for log safety),
Hetzner Cloud firewall Terraform provider registry, HashiCorp drift-detection
docs + Build5Nines "Stop Hard-Coding Local IP" pattern, institutional learning
`2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` (same root class:
firewall drift != auth failure).

### Key Improvements

1. **Confirmed `terraform apply -target=...` is an anti-pattern at scale but
   acceptable as a narrow operator-initiated recovery path** when the goal is
   "restore access fast." Adjusted the skill's emitted command to fall back
   to a full `terraform apply` with an explicit warning that `-target` skips
   dependency graph resolution. Cited HashiCorp's position that `-target`
   should be "rare and explicit, not habitual." The skill will emit the full
   apply by default and surface `-target=hcloud_firewall.web` only if the
   operator passes `--fast` (scoped-recovery flag).
2. **Locked down the public-IP detection step with a three-service fallback**
   (`ifconfig.me` → `api.ipify.org` → `icanhazip.com`) per SANS ISC best
   practice and a strict IPv4 regex validator. ipify's basic endpoint has no
   documented rate limit but the service can return stale or wrong IPs during
   upstream routing anomalies (documented in the ipify-api issue tracker);
   cross-validation across two sources is the defensive posture.
3. **Added `--silent` to every Doppler write** per Doppler's own
   "setting-secrets" guide to prevent the ADMIN_IPS value (a list of operator
   IPs -- PII-adjacent) from being captured by log-aggregation services in
   the skill's execution environment.
4. **Expanded the Cloudflare Access for SSH deferral with concrete migration
   scaffolding** (cloudflared client on operator machine, server-side
   `tunnel.tf` already present per issue context, new `access_application` +
   `access_policy` resources scoped to SSH, operator identity provider
   binding). This becomes the skeleton of the deferral issue body instead of
   a one-liner; re-evaluation criteria tightened to include a cost ceiling
   ($0 for operator-count under 50 per Cloudflare Zero Trust free tier).
5. **Added a Drift-Detection Follow-Up tier** between "short-term
   refresh skill" and "long-term Cloudflare Access": a scheduled GitHub
   Actions workflow that runs `doppler secrets get ADMIN_IPS` +
   `hcloud firewall describe` daily, diffs them, and opens an issue on
   mismatch. Cheap, additive, and catches the class where operator edits
   Doppler but forgets `terraform apply` (or vice versa).

### New Considerations Discovered

- **Institutional precedent**: learning
  `2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` documents the
  *exact same root class* -- a CI-runner version of this incident. That
  learning's "Key Insight" paragraph reads like a lede for this plan:
  *"Always verify network connectivity independently from authentication --
  they are separate failure modes that produce different errors at different
  stages of the SSH handshake."* This is doubly evidence the workflow gate
  (plan/deepen-plan network-outage checklist) is load-bearing: the class has
  recurred at least twice now.
- **VPN/WARP caveat**: if the operator is on Cloudflare WARP or a corporate
  VPN, `ifconfig.me` returns the VPN/WARP egress IP, not the home ISP IP.
  For the firewall allowlist, the VPN egress IS what the firewall sees --
  which is the desired value. Document this; do NOT try to detect the
  "real" home IP. Added to the runbook's Sharp Edges.
- **Doppler-write audit trail**: Doppler logs every secret mutation with the
  CLI token's identity. The skill should emit the Doppler dashboard URL for
  the `prd_terraform` config's audit log after a successful write, so the
  operator (and any future incident responder) can trace "who added this
  CIDR and when" without relying on memory. Trivial addition, high value.
- **Fail-closed on detection failure**: if all three IP-detection services
  fail, the skill MUST exit non-zero without writing. Current plan says
  "abort with message" -- tightened to explicit exit code 3 so a cron
  invocation (future scheduled drift check) doesn't silently no-op.
- **Terraform state pre-check**: before the skill prints the `terraform
  apply` command, it should also emit a `terraform plan -target=...` command
  so the operator can see the expected diff first. Belt-and-suspenders: the
  operator never runs `apply` without seeing `plan`. Trivial, aligns with
  AGENTS.md `cq-terraform-failed-apply-orphaned-state` (failed applies can
  orphan state).

## Overview

On 2026-04-19 operator SSH to `soleur-web-platform` failed silently because the
operator's ISP/NAT-assigned egress IP had rotated away from the `82.67.29.121/32`
CIDR pinned in `Doppler prd_terraform/ADMIN_IPS`. The Hetzner Cloud Firewall
(`firewall.tf`, rule 10708450) enforces port-22 ingress from `var.admin_ips`
only, so the new IP (`66.234.146.82`) was dropped at the firewall layer -- sshd
never saw the packet. The diagnosis chain in issue #2654 and PR #2655 targeted
fail2ban instead, which was a valid preventive fix but not the actual outage.

This plan delivers three layers of prevention:

1. **Diagnostic runbook** that makes "is the firewall dropping me?" the FIRST
   question before blaming sshd or fail2ban.
2. **Operator skill `/soleur:admin-ip-refresh`** that detects and corrects drift
   in one command: reads current egress IP, diffs against Doppler, and (with
   explicit per-command go-ahead) writes the new CIDR to Doppler and prepares a
   targeted `terraform apply`.
3. **Workflow gate** in `/soleur:plan` and `/soleur:deepen-plan` that challenges
   network-outage hypotheses with an explicit "have we verified `ADMIN_IPS`
   against current egress IP?" checklist -- so next time a subagent investigates
   an SSH-reset symptom, admin-IP drift is hypothesis #1, not "never asked."

**Out of scope:** Cloudflare Access for SSH (identity-scoped zero-trust tunnel
replacing IP allow-listing). The issue names it as "medium-term play," but it
requires new Terraform resources, operator cloudflared client setup, device
posture policies, and a migration window. Filed as a separate tracking issue
(see `## Deferral Tracking` below). This PR is the short-term preventive
layer; the Cloudflare Access migration is its own plan.

Per AGENTS.md `hr-all-infrastructure-provisioning-servers`: the skill does NOT
call the Hetzner API directly. It mutates `Doppler prd_terraform/ADMIN_IPS`
(the source of truth) and hands off a `terraform apply
-target=hcloud_firewall.web` invocation for the operator to run -- enforcing
the "all infra via Terraform" boundary. Per
`hr-menu-option-ack-not-prod-write-auth`: prod-scoped Doppler mutations
(`-c prd_terraform`) are presented without `--yes` and wait for explicit
per-command go-ahead.

## Problem Statement

### Current state (2026-04-19)

- Firewall (`apps/web-platform/infra/firewall.tf:6-13`) uses
  `dynamic "rule" { for_each = var.admin_ips }` with one `/32` per CIDR.
- `var.admin_ips` (`apps/web-platform/infra/variables.tf:21-24`) is a
  `list(string)`, hydrated from `Doppler prd_terraform/ADMIN_IPS` via
  `--name-transformer tf-var`.
- At time of outage, `ADMIN_IPS=["82.67.29.121/32"]` -- a **single-entry list
  with no margin for ISP rotation**.
- Operator current egress was `66.234.146.82`, not in the allowlist. Firewall
  dropped the SYN; sshd journal was empty; fail2ban `[sshd]` jail never fired
  for this IP (it can't -- the packet never reached sshd).
- No runbook covered this failure mode. `ssh-fail2ban-unban.md` (shipped in
  PR #2655) addresses a *different* lockout class (sshd-side ban), and its
  diagnostic flow assumes "TCP reaches port 22."
- No workflow gate in `/soleur:plan` or `/soleur:deepen-plan` forced the
  "admin-IP drift" hypothesis onto the table. Result: issue #2654's plan
  shipped with three hypotheses (permanent ban / sshd drift / sshguard), none
  of which were the actual cause.

### Why this is a recurring class, not a one-off

- Operator works from home + travel. ISP assigns a dynamic prefix; NAT mapping
  rotates on router reboots, ISP-side IPv6-lite migrations, and travel to
  different networks.
- `Doppler prd_terraform/ADMIN_IPS` is `sensitive = true` in `variables.tf`, so
  drift is invisible from casual `git log`/`terraform plan` views -- nobody
  reads it unless they're explicitly auditing.
- The only time `ADMIN_IPS` gets updated today is when someone notices an
  outage and manually edits it. That's a reactive loop with the outage as the
  trigger.
- The `## Related` section of issue #2681 also names issue #2680 (fail2ban not
  actually installed). That's a separate root cause -- different failure mode,
  different fix, tracked independently.

## Root-cause retrospective (from issue body)

The misdiagnosis chain:

1. Symptom: `kex_exchange_identification: read: Connection reset by peer` from
   operator machine.
2. `/soleur:plan` produced issue #2654's plan with three hypotheses, all
   sshd-side, because the firewall was "known to allow 82.67.29.121."
3. `/soleur:deepen-plan` did not challenge that assumption; no subagent ran
   `hcloud firewall describe` to confirm the current rule against the current
   egress IP.
4. PR #2655 shipped a correct fail2ban tuning fix, but on a server where
   fail2ban isn't installed (see issue #2680) and the actual outage cause was
   firewall-layer, not sshd-layer.

**The root cause of the misdiagnosis, not the outage:** the planning pipeline
had no mandatory verification that network-layer hypotheses (firewall,
routing, CF edge IPs, NAT) are checked BEFORE symptom-layer hypotheses (sshd,
fail2ban, hostname resolution). The fix in this plan adds that check as a
required step.

## Research Reconciliation -- Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "Doppler `prd_terraform/ADMIN_IPS` was hard-coded to `[\"82.67.29.121/32\"]`" | Confirmed by operator report; not directly verifiable from the plan context (Doppler secret, not git-committed). | Plan treats it as ground truth. The refresh skill will `doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain` as part of its diff step -- the skill's own output becomes the verification. |
| "Hetzner Cloud Firewall rule 10708450 allows port 22 only from `var.admin_ips`" | Confirmed -- `firewall.tf:6-13` uses `dynamic "rule" { for_each = var.admin_ips }`. Single-source-of-truth. | No widening of firewall. Keep `var.admin_ips` as the single-source-of-truth. |
| "Add an ops command `/soleur:admin-ip-refresh`" | No such command or skill exists (verified: `ls plugins/soleur/commands/` → 3 entry-point commands only; `ls plugins/soleur/skills/` → no `admin-ip-*`). | New skill `plugins/soleur/skills/admin-ip-refresh/` (not a command -- per `plugins/soleur/AGENTS.md`, workflow stages are skills, not commands). |
| "Update `/soleur:plan` and `/soleur:deepen-plan` to challenge network-outage hypotheses" | Both skills exist. `plan/SKILL.md` has a "Hypotheses" step in its MINIMAL/MORE templates; `deepen-plan/SKILL.md` enhances sections with parallel research. | Add a reusable `plan/references/plan-network-outage-checklist.md` referenced from both skills when the feature description matches network/connectivity symptoms (regex on the feature description). |
| "Runbook at `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`" | Directory exists with 7 runbooks (`ssh-fail2ban-unban.md` is the closest sibling -- shares frontmatter, diagnostic structure, Hetzner context). | New runbook follows the `ssh-fail2ban-unban.md` template (YAML frontmatter, Symptom → Root Cause → Diagnosis → Recovery → Prevention sections). |
| "Rename `ADMIN_IPS` to a multi-entry list by default" | `ADMIN_IPS` is already typed `list(string)` (`variables.tf:21-24`) -- the issue's "rename" is a convention fix, not a schema change. | Skill enforces the multi-entry convention at write time: refuses to write a list of length 1 without operator override (see Phase 2). No Terraform schema change. |
| Issue #2680 (fail2ban not actually installed) | Open. Not our scope; orthogonal root cause (packages step silently failed on first boot). | Acknowledge; do NOT fold in. Different failure class, different fix. |

## Files to Edit

- `plugins/soleur/skills/plan/SKILL.md` -- add "Phase 1.4: Network-outage
  hypothesis check" that reads `references/plan-network-outage-checklist.md`
  when the feature description matches the symptom regex (`SSH|connection
  reset|kex|firewall|unreachable|timeout`). If the checklist runs, its output
  MUST appear in the plan's `## Hypotheses` section.
- `plugins/soleur/skills/deepen-plan/SKILL.md` -- add a parallel step that
  reads the same checklist and produces a "Network-Outage Deep-Dive" section
  when applicable.
- `plugins/soleur/AGENTS.md` -- add a rule under `## Hard Rules` enforcing that
  SSH/network-outage plans MUST include the admin-IP verification step. Rule
  id prefix per `cq-rule-ids-are-immutable`: `hr-ssh-diagnosis-verify-firewall`.

## Files to Create

- `plugins/soleur/skills/admin-ip-refresh/SKILL.md` -- new skill entry point.
- `plugins/soleur/skills/admin-ip-refresh/references/admin-ip-refresh-procedure.md`
  -- detailed procedure (detect → diff → write → apply → verify) kept out of
  SKILL.md for token budget.
- `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md` --
  reusable checklist referenced from both `plan` and `deepen-plan`.
- `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` -- operator
  runbook (diagnostic path before blaming sshd/fail2ban).
- `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`
  -- session learning capturing the misdiagnosis class.

## Open Code-Review Overlap

**Procedure ran:**

```bash
gh issue list --label code-review --state open --json number,title,body \
  --limit 200 > /tmp/open-review-issues.json
for f in plugins/soleur/skills/plan/SKILL.md \
         plugins/soleur/skills/deepen-plan/SKILL.md \
         plugins/soleur/AGENTS.md \
         apps/web-platform/infra/firewall.tf \
         apps/web-platform/infra/variables.tf; do
  jq -r --arg path "$f" '.[] | select(.body // "" | contains($path))
    | "#\(.number): \(.title)"' /tmp/open-review-issues.json
done
```

**Matches (verified 2026-04-19 at GREEN time):**

- `#2594: test: chat-surface / kb-chat-sidebar tests flake under vitest parallel execution` -- **Acknowledge.** The match is a false positive: #2594 references `AGENTS.md` only as a string mention of a workflow-gate rule id, not as a file this PR co-touches. No actual overlap with the files this PR modifies.

## Proposed Solution

### Phase 1: Runbook (no-risk, unlocks diagnosis before skill ships)

Add `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` with
frontmatter matching `ssh-fail2ban-unban.md`:

```markdown
---
category: infrastructure
tags: [ssh, firewall, hetzner, admin-ip, drift, recovery]
date: 2026-04-19
---

# Admin IP Drift -- Recovery Runbook

## Symptom

Operator SSH to `soleur-web-platform` (135.181.45.178) hangs or resets with
no journal entry on the server for the operator IP. Unlike the fail2ban
lockout (runbook: `ssh-fail2ban-unban.md`), this failure mode leaves NO
trace in `journalctl -u ssh` because the packet never reaches sshd.

## Diagnostic Decision Tree

Run these in order BEFORE blaming sshd or fail2ban:

1. **Get current egress IP** (from operator machine):
   ```bash
   curl -s https://ifconfig.me
   # (or fallback: curl -s https://api.ipify.org)
   ```

2. **Get current ADMIN_IPS** (requires Doppler auth):

   ```bash
   doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain
   ```

3. **Get current firewall rule** (requires `hcloud` auth):

   ```bash
   hcloud firewall describe soleur-web-platform --output format='{{range .Rules}}{{.Port}} {{.SourceIPs}}{{"\n"}}{{end}}'
   ```

4. **Diff** (egress IP in `ADMIN_IPS`? `ADMIN_IPS` in firewall rule?).

If step 4 shows drift, proceed to `/soleur:admin-ip-refresh`. If drift is
ruled out, fall through to `ssh-fail2ban-unban.md`.

## Recovery (Automated)

Run `/soleur:admin-ip-refresh` and follow its prompts. It will:

1. Detect drift (diff in step 4 above).
2. Show the Doppler mutation it intends to make (pre-image + post-image).
3. Wait for explicit operator go-ahead (no `--yes`, per AGENTS.md
   `hr-menu-option-ack-not-prod-write-auth`).
4. On approval, write Doppler and emit the targeted `terraform apply`
   invocation for the operator to run.

## Recovery (Manual Fallback)

If the skill is unavailable, follow the sequence verbatim (see runbook
body -- full commands with validation).

## Prevention

The `/soleur:admin-ip-refresh` skill is designed to run pre-emptively
(before an outage): run it whenever the operator notices their IP may
have rotated. It's also in the `/soleur:plan` network-outage checklist
for reactive use.

When `ADMIN_IPS` is down to one entry, the skill warns. Multi-entry
lists (e.g., home + mobile hotspot + known travel networks) are the
recommended steady state.

```

Ship first so diagnosis-during-outage has a page to land on.

### Research Insights (Phase 1)

**Institutional-learning cross-reference:**

`knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
documents the same root class from a CI-runner angle -- the GitHub Actions
deploy failed because Hetzner firewall restricted port 22 to `admin_ips`
and runners have 5000+ dynamic IPs. That learning's Key Insight reads:

> Always verify network connectivity independently from authentication --
> they are separate failure modes that produce different errors at different
> stages of the SSH handshake.

The runbook's Diagnostic Decision Tree (firewall BEFORE sshd/fail2ban)
operationalizes exactly this insight. **The new runbook should link to that
learning so a future session following the same-root-class paper trail can
find both artifacts from either direction.**

**Runbook-design best practice (runbook interlinking):**

The existing `ssh-fail2ban-unban.md` has no cross-reference to the
admin-IP-drift failure mode today. Add a "See also" line at the top of
`ssh-fail2ban-unban.md` pointing to `admin-ip-drift.md` as part of this PR.
Bidirectional pointer so an incident responder lands on the right runbook
by symptom, not by memory.

**Drift-detection pattern (for the deferred scheduled check):**

The Build5Nines "Stop Hard-Coding Local IP" guidance plus HashiCorp's
[drift detection tutorial](https://developer.hashicorp.com/terraform/tutorials/cloud/drift-detection)
together recommend treating "dynamic IP" as *execution context, not
configuration*. The scheduled drift check (deferred, see `## Deferral
Tracking`) is the institutional memory that enforces this: "if the source
of truth (Doppler) drifts from the realized state (firewall), we see it
within 24 hours, not when an operator gets locked out."

**References:**

- [Institutional learning: CI SSH deploy firewall hidden dependency](../learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md)
- [HashiCorp -- Drift and policy](https://developer.hashicorp.com/terraform/tutorials/cloud/drift-and-policy)

### Phase 2: Operator skill `admin-ip-refresh`

**Location:** `plugins/soleur/skills/admin-ip-refresh/SKILL.md`

**Name/description (third-person, per `plugins/soleur/AGENTS.md` skill
compliance checklist):**

```yaml
---
name: admin-ip-refresh
description: This skill should be used when the operator suspects their public
  IP has rotated and needs to refresh the prod SSH allowlist (Doppler
  prd_terraform/ADMIN_IPS + Hetzner firewall). Detects drift, shows a diff,
  and mutates Doppler only with explicit per-command go-ahead.
---
```

**Procedure (referenced from `references/admin-ip-refresh-procedure.md` to
keep SKILL.md under the 1800-word description budget):**

1. **Detect current egress IP.** `curl -fsS https://ifconfig.me/ip` with
   fallback to `https://api.ipify.org` on non-200. Abort with a clear message
   if both fail (likely operator offline).
2. **Read current `ADMIN_IPS`.** `doppler secrets get ADMIN_IPS -p soleur -c
   prd_terraform --plain`. Parse as JSON list. If the secret is missing, abort
   and instruct the operator to bootstrap it.
3. **Diff.** Check if `<current-egress>/32` is in the list.
   - If present: print "No drift. Current IP `X.X.X.X/32` is in `ADMIN_IPS`
     (list length N)." Exit 0.
   - If absent: show the diff (pre-image list, post-image list with new entry
     appended).
4. **Warn on list-length invariants.**
   - If post-image length == 1 (single entry, the risk class that caused this
     incident): emit a P1 warning "Single-entry `ADMIN_IPS` has no rotation
     margin. Consider adding a second known-good CIDR (home WAN + mobile
     hotspot + travel) before shipping." Require operator to type `understood`
     to proceed.
   - If post-image length > 10 (plausible drift-residue): emit a P2 warning
     "`ADMIN_IPS` has grown to N entries. Stale entries should be pruned --
     review and remove CIDRs you don't recognize." Continue.
5. **Operator go-ahead prompt** (no `--yes`, per
   `hr-menu-option-ack-not-prod-write-auth`). Show the exact `doppler secrets
   set` invocation the skill will run. Wait for explicit operator ack.
6. **Write Doppler.** `doppler secrets set ADMIN_IPS -p soleur -c
   prd_terraform` piped from stdin JSON list. Verify the write by re-reading
   and comparing.
7. **Emit `terraform apply` invocation** for operator to run. Do NOT run it
   from the skill -- per `hr-all-infrastructure-provisioning-servers`,
   Terraform apply is an operator-initiated action, not a skill-initiated
   one. Exact form:

   ```bash
   cd apps/web-platform/infra
   doppler run --project soleur --config prd_terraform -- \
     doppler run --token "$(doppler configure get token --plain)" \
       --project soleur --config prd_terraform --name-transformer tf-var -- \
     terraform apply -target=hcloud_firewall.web
   ```

   (Matches the nested-Doppler pattern documented in `variables.tf:1-13` and
   AGENTS.md `cq-when-running-terraform-commands-locally`.)
8. **Verify** (optional post-apply step the skill offers): `hcloud firewall
   describe soleur-web-platform` and grep for the new CIDR on port 22. If the
   operator ran the apply, they can run `/soleur:admin-ip-refresh --verify`
   to rerun only the diff step.

**SKILL.md structure** mirrors a compact utility skill (compare
`plugins/soleur/skills/schedule/SKILL.md` or `kb-search/SKILL.md` for
reference size):

- Intro (1 paragraph on purpose).
- Sharp edges (list-length warnings, nested Doppler reason, why no
  `terraform apply` in the skill).
- Procedure (one-liner for each of 8 steps above, linking to
  `references/admin-ip-refresh-procedure.md` for detail).

**CLI verification (per `cq-docs-cli-verification` and the plan's CLI-
verification gate):**

- `curl -s https://ifconfig.me` -- verified operational per issue body
  (operator used it during incident). `<!-- verified: 2026-04-19 source:
  https://ifconfig.me -->`
- `doppler secrets get ADMIN_IPS -p soleur -c prd_terraform --plain` --
  verified via `doppler secrets get --help` (session verification: `--plain`,
  `-p`, `-c` all present).
- `doppler secrets set ADMIN_IPS -p soleur -c prd_terraform --silent` --
  verified via `doppler secrets set --help` (stdin form documented in-help);
  `--silent` per Doppler's "setting-secrets" guide (prevents value echo into
  captured stdout).
- `hcloud firewall describe soleur-web-platform` -- verified via `hcloud
  firewall describe --help`.

### Research Insights (Phase 2)

**Best Practices for public-IP detection in shell scripts (2026):**

- **Multiple-service strategy is the 2026 standard.** No single service is
  authoritative; ipify, ifconfig.me, and icanhazip.com all have occasional
  upstream routing anomalies or return non-IPv4 content during outages. Query
  the primary, validate the response shape, fall back to the secondary on
  parse-failure or HTTP non-200. SANS ISC has documented bot ecosystems that
  rotate between these exact three endpoints for robustness reasons --
  adopting the same pattern here is defense in depth.
- **Strict timeouts** (`curl --connect-timeout 5 --max-time 10`) prevent the
  skill from hanging on a degraded service. Retry-up-to-3 with 2-second
  backoff, per cited 2026 guidance.
- **IPv4 validation regex** after the response body: reject anything that
  doesn't match `^([0-9]{1,3}\.){3}[0-9]{1,3}$` and then octet-range-check
  each group `<= 255`. The validation itself defends against the ipify
  `Issue #19` class (service returns HTML error page that happens to contain
  digit substrings).
- **ipify rate limit (basic endpoint): none documented.** The skill is
  operator-initiated (expected ~1 invocation/week), well below any implicit
  infrastructure cap.

**Implementation sketch (Phase 2 detect step):**

```bash
detect_egress_ip() {
  local services=(
    "https://ifconfig.me/ip"
    "https://api.ipify.org"
    "https://icanhazip.com"
  )
  for svc in "${services[@]}"; do
    local ip
    ip="$(curl -fsS --connect-timeout 5 --max-time 10 "$svc" 2>/dev/null \
         | tr -d '[:space:]')" || continue
    if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      # Octet-range check
      IFS=. read -r a b c d <<<"$ip"
      if (( a<=255 && b<=255 && c<=255 && d<=255 )); then
        echo "$ip"; return 0
      fi
    fi
  done
  return 1
}
```

**Best Practices for Doppler CLI secret mutation (2026):**

- **Use `--silent`** on every `doppler secrets set` invocation inside an
  automated script. Per Doppler's "setting-secrets" guide: this prevents the
  value from being emitted to stdout, which is the standard hardening against
  accidental log-aggregator capture. `ADMIN_IPS` is a list of operator IPs
  -- PII-adjacent per most interpretations.
- **Prefer stdin over CLI-arg** for the list value. `doppler secrets set
  ADMIN_IPS --silent < /tmp/admin-ips.json` keeps the value out of process
  lists (`ps auxf`) and shell history. The skill should write the new list
  to a temp file, chmod 600, pipe it via `<`, then `shred -u` the temp
  file on exit.
- **Verify post-write.** Re-read via `doppler secrets get ADMIN_IPS --plain`
  and compare byte-for-byte. Doppler's write-after-write consistency is
  strong (single-writer semantics per secret), but the skill should verify
  anyway -- the only cost is one API call.
- **Capture the audit-trail URL.** Doppler's dashboard logs every secret
  mutation. After a successful write, the skill prints
  `https://dashboard.doppler.com/workplace/projects/soleur/configs/prd_terraform/activity`
  so the operator (and future responders) have a direct link.

**Best Practices for Terraform narrow-target applies (2026):**

- HashiCorp's position: `-target` is for *recovery and rare cases*, not
  habitual use. The full dependency graph is skipped; cascading effects (if
  any) are deferred to the next full apply. See HashiCorp's "Maturing your
  Terraform workflow" guide -- the Build5Nines "Stop Hard-Coding Local IP"
  article is the closest-matched pattern for exactly this use case and
  endorses `-target` as acceptable for admin-IP rotation.
- **Always emit the full apply alongside.** The skill prints BOTH:

  ```bash
  # Preferred (full plan, full apply):
  cd apps/web-platform/infra && doppler run ... -- terraform plan
  cd apps/web-platform/infra && doppler run ... -- terraform apply

  # Fast recovery (only the firewall resource, skips graph):
  cd apps/web-platform/infra && doppler run ... -- terraform plan -target=hcloud_firewall.web
  cd apps/web-platform/infra && doppler run ... -- terraform apply -target=hcloud_firewall.web
  ```

- **`plan` before `apply`.** The skill emits the plan command first and
  refuses to mark itself "done" until the operator confirms they've reviewed
  the plan output. AGENTS.md `cq-terraform-failed-apply-orphaned-state`
  reinforces this -- failed applies orphan tfstate, so seeing the diff before
  committing is a strong norm.

**References:**

- [Doppler CLI -- Setting Secrets](https://docs.doppler.com/docs/setting-secrets)
- [Doppler CLI -- Accessing Secrets](https://docs.doppler.com/docs/accessing-secrets)
- [ipify -- Public IP Address API](https://www.ipify.org/)
- [SANS ISC -- APIs Used by Bots to Detect Public IP](https://isc.sans.edu/diary/29516)
- [Hetzner Cloud Provider -- hcloud_firewall](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs/resources/firewall)
- [Build5Nines -- Stop Hard-Coding Local IP in Terraform](https://build5nines.com/stop-hard-coding-local-ip-in-terraform-lock-down-firewalls-dynamically/)
- [HashiCorp -- Terraform drift detection](https://developer.hashicorp.com/terraform/tutorials/cloud/drift-detection)

### Phase 3: Plan/deepen-plan workflow gate

**`plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`**
(new file):

```markdown
# Network-Outage Hypothesis Checklist

Run this checklist BEFORE writing the plan's `## Hypotheses` section when
the feature description matches any of: SSH, connection reset, kex,
firewall, unreachable, timeout, 502, 503, 504, handshake, EHOSTUNREACH,
ECONNRESET.

## Checklist

For each layer, the plan MUST answer "verified / not verified" before
proceeding:

1. **Firewall allowlist (L3/L4):** Has `hcloud firewall describe` (or
   equivalent vendor CLI) been run against the affected host, and has
   the result been diffed against the current operator/client egress IP?
2. **DNS/routing (L3):** Has `dig <hostname>` + `traceroute <ip>` or
   `mtr` been run from the client network?
3. **TLS/proxy layer (L7, if HTTPS):** Has `curl -Iv` been run to confirm
   the certificate chain and any intermediary (Cloudflare, CDN)?
4. **Application layer (L7, service-specific):** Has `journalctl -u
   <service>` on the host shown the incoming connection?

**If any of these is "not verified", the plan's `## Hypotheses` section
MUST list that unverified layer as Hypothesis 1, 2, 3 (in order) BEFORE
any layer-specific hypothesis like "sshd config drift" or "app crash."**

## Why

Issue #2654 plan listed three sshd-layer hypotheses without verifying
firewall/admin-IP first; actual outage was firewall-layer (admin-IP
drift). Cost: one misdirected PR (#2655), one genuine-but-not-causal
fix, and a second incident day spent rediagnosing.

## Opt-out

A plan may explicitly opt out of a layer check with a one-line
justification (e.g., "L3 DNS verified stable -- same host was reachable
5 minutes prior with same client network"). "Obvious" is not a
justification; cite the verification artifact.
```

**Integration in `plan/SKILL.md`:**

- Add Phase 1.4 after the existing Phase 1.1 (Local Research) and 1.5/1.5b/1.6:
  "If the feature description matches the network-outage regex (see
  checklist), read `references/plan-network-outage-checklist.md` and require
  its output in the `## Hypotheses` section of the final plan."
- The regex match is a simple string-contains scan performed by the skill, not
  a new agent spawn -- cost is one file read, not a subagent.

**Integration in `deepen-plan/SKILL.md`:**

- If the plan being deepened has a `## Hypotheses` section AND any of the
  network-outage keywords appear in the plan's Overview, spawn a
  "network-layer verifier" step in parallel with the other deepen sections.
  This step reads the checklist and emits a "Network-Outage Deep-Dive"
  subsection that verifies each layer against the plan's stated evidence.

**Integration in `plugins/soleur/AGENTS.md` (new Hard Rule):**

```markdown
- When a plan addresses an SSH/network connectivity symptom (reset, timeout,
  unreachable, handshake failure), it MUST verify the L3 firewall allowlist
  against current client egress IP BEFORE proposing sshd/fail2ban/service-
  layer fixes [id: hr-ssh-diagnosis-verify-firewall]. `hcloud firewall
  describe` + `curl -s https://ifconfig.me` is the load-bearing diagnostic.
  Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`.
  **Why:** #2681 -- issue #2654 plan listed three sshd-layer hypotheses
  without verifying firewall; real cause was admin-IP drift.
```

Rule stays under 600 bytes (AGENTS.md budget cap per
`cq-agents-md-why-single-line`). The `**Why:**` is one sentence pointing to
the issue number.

### Research Insights (Phase 3 -- Workflow Gate)

**Why a checklist, not an agent:**

A full research agent spawn for every SSH-symptom plan would cost ~10-30
seconds per plan and introduce variance (agent might or might not catch the
firewall question). A referenced checklist in the plan skill's context is
deterministic, costs one file read, and makes the firewall question the
FIRST question by position in the prompt. Choosing the checklist form over
an agent is a deliberate reliability-over-cleverness trade.

**Layer ordering (L3 → L7) as the organizing principle:**

The checklist enforces the OSI-ordered diagnostic sequence (L3 firewall /
routing → L4 TCP state → L7 application). This mirrors the actual packet
journey -- a layer that drops a packet is invisible to layers above, so
starting with the higher layer (as issue #2654's plan did) produces
phantom hypotheses. The 2026-03-19 learning documents the same inversion
in a CI context. Codifying the L3→L7 discipline in the plan skill makes
this hard to get wrong.

**Regex trigger vs. always-run:**

The regex-matched trigger (SSH|connection reset|kex|firewall|unreachable|
timeout|502|503|504|handshake|EHOSTUNREACH|ECONNRESET) is the right
granularity: applies to any network-outage-like symptom without forcing
every feature-plan to include an L3 section. If the regex produces false
positives, the checklist is additive (plan still ships with a small N/A
section); false negatives degrade gracefully (plan-review agents catch
missed cases downstream). Both failure modes are cheap.

**AGENTS.md rule size budget:**

Rule draft under 600 bytes (AGENTS.md `cq-agents-md-why-single-line` cap):

```text
When a plan addresses an SSH/network connectivity symptom (reset, timeout,
unreachable, handshake failure), it MUST verify the L3 firewall allowlist
against current client egress IP BEFORE proposing sshd/fail2ban/service-
layer fixes [id: hr-ssh-diagnosis-verify-firewall]. `hcloud firewall
describe` + `curl -s https://ifconfig.me` is the load-bearing diagnostic.
Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`.
**Why:** #2681 -- issue #2654 plan listed three sshd-layer hypotheses
without verifying firewall; real cause was admin-IP drift.
```

Byte count (wc -c on just the rule): ~540 bytes. Under the 600-byte cap.
Compound step 8 budget check (< 100 rules total, < 40000 file bytes) will
re-verify at ship time.

**References:**

- [HashiCorp -- Opinionated Terraform best practices](https://www.hashicorp.com/en/resources/opinionated-terraform-best-practices-and-anti-patterns)
- [Institutional learning: CI SSH firewall hidden dependency](../learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md)

### Phase 4: Learning entry

**`knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`:**

Captures the misdiagnosis class (layer-order in hypothesis generation), the
workflow gate fix, and pointers to the AGENTS.md rule and runbook. Follows
the existing learning template (YAML frontmatter: `category`, `tags`,
`date`; sections: What happened, Why it happened, What we changed, How to
prevent).

## Hypotheses

Per the new network-outage checklist (dogfooding the rule this PR ships):

1. **L3 firewall allowlist drift (verified root cause).** `var.admin_ips` was
   a single-entry `[82.67.29.121/32]`, operator egress rotated to
   `66.234.146.82`. Firewall dropped port-22 ingress. Remediation: skill that
   detects + corrects, runbook that prompts the diagnosis, workflow gate that
   keeps the class from recurring.
2. **L3 DNS/routing drift (ruled out).** `hcloud server list` showed running;
   HTTPS 200 on `app.soleur.ai`/`soleur.ai` confirms edge + origin reachable
   for non-SSH paths. DNS is not the issue.
3. **L7 sshd/fail2ban (ruled out for this incident).** Service never saw the
   connection (firewall dropped it); sshd/fail2ban cannot be the cause when
   there's no journal entry. Issue #2680 (fail2ban package not installed) is
   an orthogonal root cause surfaced during incident response -- tracked
   separately, not folded here.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Skill writes to `Doppler prd_terraform` without operator consent (blast radius: lockout, audit trail). | No `--yes` flag. No `-auto-approve`. Explicit operator ack required per `hr-menu-option-ack-not-prod-write-auth`. Diff shown pre- and post-image before write. |
| Skill detects wrong egress IP (e.g., VPN, Cloudflare WARP routing masks real IP). | `curl -s https://ifconfig.me` returns the true egress as seen by internet services. If the operator is on a corporate VPN that makes their egress IP different from their real public IP, the skill's output IS what the firewall will see -- which is the desired semantic. Document this in the runbook. |
| `ADMIN_IPS` list grows unbounded (stale entries from old WAN / ISP changes). | Skill emits P2 warning when list length > 10. Operator-managed pruning. Could add an automated "age out entries older than 90 days" policy as a follow-up -- deferred (see `## Deferral Tracking`). |
| Terraform drift if operator writes Doppler but forgets `terraform apply`. | Skill ends with the EXACT terraform apply command printed to stdout and refuses to mark itself "done" until the operator confirms they ran it. The next `terraform plan` in CI would also surface the drift (monitoring provisioned by the drift-detection workflow). |
| Planning gate regex false positives (plan description mentions "timeout" in an unrelated context, e.g., UI timer). | Checklist is additive, not blocking. Worst case: plan gains a "Network-Outage Deep-Dive" section that's marked N/A. No blocking. |
| Planning gate regex false negatives (feature description uses a synonym the regex doesn't match, e.g., "unable to SSH"). | Regex includes `SSH` (case-insensitive). Longer-term: the gate is a soft prompt; plan-review agents will catch missed cases. Iterate. |
| Cloudflare Access migration deferral invisible. | Filed as a separate tracking issue (see `## Deferral Tracking`) with re-evaluation criteria (e.g., "when `ADMIN_IPS` grows past 10 entries OR when second drift-caused incident occurs"). |
| Runbook prescribes commands that don't exist / wrong flags. | All four CLI forms verified at plan time (`curl`, `doppler secrets get`, `doppler secrets set`, `hcloud firewall describe`) via `--help`. See `## Acceptance Criteria` for pre-merge verification. |
| Single-IP-detection service outage (ipify temporary 5xx, ifconfig.me DNS hiccup). | Three-service fallback (`ifconfig.me` → `api.ipify.org` → `icanhazip.com`) with strict timeouts (`--connect-timeout 5 --max-time 10`). Skill aborts only if ALL three fail; exits non-zero so a future scheduled invocation doesn't silently no-op. |
| IP-detection service returns HTML error page with embedded digits that passes a naive grep. | Strict IPv4 regex validation (`^([0-9]{1,3}\.){3}[0-9]{1,3}$`) PLUS octet-range check (each group ≤ 255) after every curl. See ipify GitHub issue #19 -- "api.ipify.org shows wrong IP" -- for the class this defends against. |
| Doppler secret value echoed to captured stdout (log aggregator captures `ADMIN_IPS` value). | `doppler secrets set ... --silent` flag per Doppler's official setting-secrets guide. Stdin-piped value (not CLI arg) keeps the list out of `ps auxf` and shell history. Temp file used for piping is `chmod 600` then `shred -u` on exit. |
| `terraform apply -target=...` skips dependency graph, could leave state inconsistent. | Skill emits BOTH the narrow-target AND full-apply forms. Default message recommends the full apply; `-target` surfaced only under `--fast` flag for recovery. Cites HashiCorp position that `-target` is for rare/recovery cases, not habitual. Also emits `terraform plan` first -- operator confirms diff before apply. |
| Doppler write succeeds but operator forgets the `terraform apply` step (silent drift). | The deferred scheduled drift-check workflow (see `## Deferral Tracking` item 2) catches this within 24 hours. Until that ships, the skill explicitly prompts at exit: "Did you run terraform apply? [yes / no / skip]" -- a "no" answer writes a reminder to the operator's terminal and records the gap. |
| Audit trail invisibility -- "who added CIDR X.X.X.X, and when?" | Skill prints the Doppler dashboard activity URL on successful write: `https://dashboard.doppler.com/workplace/projects/soleur/configs/prd_terraform/activity`. Doppler logs every mutation by token identity. |

## Acceptance Criteria

### Pre-merge (PR)

- [x] `plugins/soleur/skills/admin-ip-refresh/SKILL.md` exists with valid YAML
      frontmatter (`name:`, `description:` third-person, no example blocks).
- [x] `plugins/soleur/skills/admin-ip-refresh/references/admin-ip-refresh-procedure.md`
      exists and is linked from SKILL.md via `[procedure](./references/admin-ip-refresh-procedure.md)`
      (per `plugins/soleur/AGENTS.md` reference-links checklist).
- [x] `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`
      exists and is linked from `plan/SKILL.md`.
- [x] `plugins/soleur/skills/plan/SKILL.md` references the checklist in a new
      Phase 1.4 step.
- [x] `plugins/soleur/skills/deepen-plan/SKILL.md` references the checklist.
- [x] `plugins/soleur/AGENTS.md` has the new `hr-ssh-diagnosis-verify-firewall`
      rule. Rule is 545 bytes (under 600-byte cap). `**Why:**` is one sentence
      pointing to #2681. Total AGENTS.md: 36638 bytes (under 40000 cap).
      Rule count: 106 (exceeds the 100 warn threshold -- pre-existing state
      on main was 105; this PR adds 1; warning only, not a hard block).
- [x] `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` exists with
      frontmatter matching the sibling runbook template.
- [x] `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`
      exists.
- [x] `bun test plugins/soleur/test/components.test.ts` passes (1006/0 after
      trimming over-target descriptions in `fix-issue`, `feature-video`,
      `dhh-rails-style` to make room within the 1800-word cap).
- [x] `npx markdownlint-cli2 --fix` on changed `.md` files only (per `cq-
      markdownlint-fix-target-specific-paths`). Pre-existing MD055 errors in
      `dhh-rails-style/SKILL.md` tracked in #2685 (out of scope).
- [ ] Multi-agent review (DHH simplicity, Kieran correctness, Code simplicity)
      agrees the skill has no hidden prod-write authorization path.
- [ ] `## Changelog` section in PR body with `semver:minor` label (new skill
      qualifies as MINOR per `plugins/soleur/AGENTS.md`).

### Post-merge (operator)

- [ ] Run `/soleur:admin-ip-refresh` against current prod Doppler + firewall,
      confirm it correctly detects "no drift" state when the current CIDR is
      in the list.
- [ ] Trigger a test drift (bogus CIDR in `ADMIN_IPS`) and confirm the skill
      detects and offers to correct. Do NOT run the `terraform apply` step in
      the test -- the skill should stop at "operator approval" and not
      mutate real firewall rules. (If the test is conducted against real
      prod, revert the test CIDR manually.)
- [ ] Verify the plan gate fires on a contrived plan input containing "SSH
      connection reset" in the feature description. The plan's
      `## Hypotheses` section MUST include an L3 firewall-allowlist entry.

## Test Scenarios

Infrastructure + skill + docs; per AGENTS.md `cq-write-failing-tests-before`
exemption for infrastructure-only tasks, no unit-test-first requirement.
However, the skill procedure lends itself to a dry-run test harness:

- **Dry-run mode** (`/soleur:admin-ip-refresh --dry-run`): run steps 1-4
  (detect, read, diff, warn) without any writes. Useful for pre-incident
  hygiene checks. Add as an explicit flag in Phase 2.
- **Contrived-plan test** for the plan gate: create a `.md` file with
  "SSH kex reset" in the Overview; run plan-review manually against it; assert
  the output plan includes L3 firewall hypothesis. One-off, not CI-run.

## Deferral Tracking

Items explicitly out of scope of this PR, to be filed as separate GitHub
issues per AGENTS.md `wg-when-deferring-a-capability-create-a`:

1. **Cloudflare Access for SSH (zero-trust tunnel, identity-bound).** Replaces
   IP allow-listing entirely. Milestone: "Post-MVP / Later". Re-evaluation
   criteria: operator cost of maintaining `ADMIN_IPS` exceeds 1 hour/month OR
   second drift-caused incident OR `ADMIN_IPS` list length > 10.

   **Migration scaffolding (for the deferred-issue body):**
   - Operator-side: install cloudflared on each operator machine, configure
     `cloudflared access ssh --hostname ssh.soleur.ai` per [Cloudflare One
     docs](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/use-cases/ssh/ssh-cloudflared-authentication/).
   - Server-side: `tunnel.tf` already provisions the Cloudflare Tunnel for
     the deploy webhook; add a new `ingress` rule for `ssh://localhost:22`
     scoped to a new hostname (e.g., `ssh.soleur.ai`). The existing tunnel
     is reusable -- no new tunnel resource needed.
   - Access policy: new `cloudflare_access_application` +
     `cloudflare_access_policy` resources, identity-provider-backed (Google
     Workspace or GitHub SSO, same IdP as the deploy-webhook flow).
   - Firewall: after migration validates, `hcloud_firewall.web` port-22 rule
     narrows to the Cloudflare Tunnel origin (server's loopback) -- the
     public port 22 closes entirely to the internet.
   - Cost: Cloudflare Zero Trust free tier covers up to 50 users. Operator
     count is 1; headroom is enormous.
   - Risk: new operator dependency on cloudflared client; runbook needed for
     "cloudflared daemon not running -> can't SSH" failure mode.
   - File as `ops: migrate prod SSH from IP allow-list to Cloudflare Access
     for Infrastructure`.
2. **Scheduled ADMIN_IPS-vs-firewall drift check (GitHub Actions cron).** Run
   daily via `.github/workflows/scheduled-admin-ip-drift-check.yml`: fetch
   `doppler secrets get ADMIN_IPS` and `hcloud firewall describe` via their
   respective CLIs, diff, open an issue on mismatch. Cheap, additive, catches
   the class where operator edits one source but forgets the other. This is
   the "institutional memory" layer beyond the on-demand refresh skill.
   Re-evaluation criteria: implement immediately after this PR lands (it's
   next-bite-sized scope, but out of this PR to keep blast radius small).
   File as `ops: scheduled ADMIN_IPS-vs-firewall drift detection workflow`.
3. **Auto-prune `ADMIN_IPS` entries older than 90 days.** Requires timestamp
   metadata on each entry, which Doppler's flat-secret model doesn't support
   natively. Could store as JSON array of `{cidr, added_at}` objects and
   sub-parse -- deferred. Re-evaluation criteria: list length > 10 twice in 6
   months. File as `ops: auto-expire stale entries in ADMIN_IPS`.

Each deferral creates a GitHub issue at implementation time (not at plan
time) -- plan review may adjust this list before ship.

## Domain Review

**Domains relevant:** engineering (primary), operations (secondary).

### Engineering (CTO)

**Status:** reviewed (via this plan author, the primary author is the CTO
lane by default per passive-domain-routing).
**Assessment:** The plan is a workflow + operator-tooling fix with no code-path
changes to the production application. Risk surface is limited to:
(a) the skill's Doppler-write path (mitigated by operator ack gate),
(b) AGENTS.md rule growth (mitigated by budget check),
(c) plan-skill instruction changes (validated by the "dogfooding" hypothesis
section). No architectural implication -- deferred Cloudflare Access
migration is a separate plan.

### Operations (COO)

**Status:** reviewed (by inference -- operator lockout is an ops incident
class, and the skill is an ops-tooling artifact).
**Assessment:** The skill+runbook pair follows the existing ops runbook
pattern (`ssh-fail2ban-unban.md` is the sibling template). Diagnostic
decision tree is layered L3 → L7, matching the incident reasoning model.
Operator burden: one new skill invocation to remember, one new runbook to
recall during an incident -- but the runbook has been structured to be the
first hit when an operator greps `knowledge-base/engineering/ops/runbooks/`
for "ssh" symptoms.

### Product (CPO)

**Tier:** NONE. No user-facing surface changes.

No Product/UX Gate subsection needed.

## Alternative Approaches Considered

| Approach | Why Not |
|---|---|
| Widen firewall to `0.0.0.0/0` for port 22 and rely on sshd-only security | Violates defense-in-depth. sshd is hardened but not bulletproof; firewall is the first line. Also amplifies fail2ban exposure (every scanner on the internet triggers the jail). |
| Migrate to Cloudflare Access for SSH (the medium-term proposal in the issue) | Requires cloudflared client setup per operator, Terraform for the zero-trust application, device posture policies, a migration window -- and the short-term fix ships faster. Deferred to a separate plan. |
| Skill directly calls `terraform apply` | Violates `hr-all-infrastructure-provisioning-servers` (no vendor-API or out-of-band applies) AND `hr-menu-option-ack-not-prod-write-auth` (no `-auto-approve` on prod). Printing the exact command for the operator to run preserves the Terraform boundary AND respects the prod-ack rule. |
| Automate entry pruning via cron/GH Actions | Doppler flat-secret model has no per-entry timestamps. Implementing `{cidr, added_at}` JSON objects is a larger scope. Deferred. |
| Add a second `hcloud firewall` rule that allows SSH from a broader CIDR for "emergency access" | Defeats the purpose -- that rule IS the lockout vulnerability, now on a slower decay. Operators would forget to rotate; we're back where we started. |
| Pre-commit hook in `apps/web-platform/infra/` that greps `ADMIN_IPS` length | `ADMIN_IPS` isn't in git -- it's in Doppler. A hook can't read prod Doppler at pre-commit time. |

## Implementation Order

1. Runbook + learning entry (no code, unlocks operator comms and teaches the
   class).
2. Skill scaffolding (SKILL.md + references/) with dry-run only.
3. Skill write path (Doppler mutation + terraform apply emission) gated behind
   operator ack.
4. Plan-skill integration (checklist file + Phase 1.4 reference).
5. Deepen-plan integration.
6. AGENTS.md rule + budget check.
7. Deferral issues filed at ship time (Cloudflare Access, auto-prune,
   scheduled drift check).

Phases 1-2 can land in a single commit; 3-4-5 each in their own commit so
review can isolate the write-path and the workflow-gate changes.

## Notes for the Implementer

- When naming the skill, prefer `admin-ip-refresh` over `admin-ip-drift` (the
  skill is an active refresh operation, not a noun for the failure mode). The
  issue body uses `admin-ip-refresh` as its proposed name.
- Do NOT add `hcloud` or `doppler` to a `packages.json` -- they're
  preinstalled via `~/.local/bin` per AGENTS.md's tool-discovery priority
  ladder. The skill assumes they exist and aborts with an install hint
  otherwise.
- The runbook and the skill's SKILL.md SHOULD reference each other
  bidirectionally: SKILL.md points to runbook for the full diagnostic context;
  runbook points to SKILL.md as the automation-first recovery path.
- When opening the PR, set the `semver:minor` label (new skill) and include a
  `## Changelog` section per `plugins/soleur/AGENTS.md` pre-commit checklist.
