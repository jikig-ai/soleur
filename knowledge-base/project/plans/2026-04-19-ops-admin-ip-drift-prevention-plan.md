---
title: "ops: prevent admin-IP drift from causing prod SSH lockouts"
type: ops
date: 2026-04-19
semver: minor
issue: 2681
---

# ops: prevent admin-IP drift from causing prod SSH lockouts

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

**Matches:** To be verified at GREEN time. If the grep returns rows, add
disposition here before shipping (fold-in vs. acknowledge vs. defer per
`plan-functional-overlap.md`).

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
- `doppler secrets set ADMIN_IPS -p soleur -c prd_terraform` -- verified via
  `doppler secrets set --help` (stdin form documented in-help).
- `hcloud firewall describe soleur-web-platform` -- verified via `hcloud
  firewall describe --help`.

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

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/skills/admin-ip-refresh/SKILL.md` exists with valid YAML
      frontmatter (`name:`, `description:` third-person, no example blocks).
- [ ] `plugins/soleur/skills/admin-ip-refresh/references/admin-ip-refresh-procedure.md`
      exists and is linked from SKILL.md via `[procedure](./references/admin-ip-refresh-procedure.md)`
      (per `plugins/soleur/AGENTS.md` reference-links checklist).
- [ ] `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`
      exists and is linked from `plan/SKILL.md`.
- [ ] `plugins/soleur/skills/plan/SKILL.md` references the checklist in a new
      Phase 1.4 step.
- [ ] `plugins/soleur/skills/deepen-plan/SKILL.md` references the checklist.
- [ ] `plugins/soleur/AGENTS.md` has the new `hr-ssh-diagnosis-verify-
      firewall` rule. Rule is under 600 bytes. `**Why:**` is one sentence.
      Rule count and AGENTS.md total bytes under the compound step 8 budget
      caps (< 100 rules, < 40000 file bytes).
- [ ] `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md` exists with
      frontmatter matching the sibling runbook template.
- [ ] `knowledge-base/project/learnings/bug-fixes/2026-04-19-admin-ip-drift-misdiagnosed-as-fail2ban.md`
      exists.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (skill
      description token budget preserved -- new skill adds a small amount to
      cumulative count).
- [ ] `npx markdownlint-cli2 --fix` on changed `.md` files only (per `cq-
      markdownlint-fix-target-specific-paths`).
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
   IP allow-listing. Milestone: "Post-MVP / Later" (promote when list length
   > 10, or second drift-caused incident). Re-evaluation criteria: operator
   cost of maintaining `ADMIN_IPS` exceeds 1 hour/month OR second incident.
   File as `ops: migrate prod SSH from IP allow-list to Cloudflare Access`.
2. **Auto-prune `ADMIN_IPS` entries older than 90 days.** Requires timestamp
   metadata on each entry, which Doppler's flat-secret model doesn't support
   natively. Could store as JSON array of `{cidr, added_at}` objects and
   sub-parse -- deferred. Re-evaluation criteria: list length > 10 twice in 6
   months. File as `ops: auto-expire stale entries in ADMIN_IPS`.
3. **`/soleur:admin-ip-refresh --verify` as a scheduled health check.** Run on
   a cron (GitHub Actions) and emit an issue if `hcloud firewall describe`
   drifts from Doppler `ADMIN_IPS`. Out of scope here (the skill is operator-
   initiated, not scheduled). File as `ops: scheduled ADMIN_IPS-vs-firewall
   drift check`.

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
