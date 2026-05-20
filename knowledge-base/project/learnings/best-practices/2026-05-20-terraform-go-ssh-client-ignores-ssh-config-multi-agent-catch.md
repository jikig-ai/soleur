---
date: 2026-05-20
category: best-practices
tags:
  - terraform
  - ssh
  - cloudflare-tunnel
  - plan-time-verification
  - multi-agent-review
related_pr: 4181
related_issue: 4177
---

# Terraform's Go SSH client ignores `~/.ssh/config` — multi-agent review caught the load-bearing assumption deepen-plan missed

## Problem

PR #4181 (fix for #4177 "Apply deploy-pipeline-fix.yml CI→host SSH timeout")
shipped through `/soleur:plan`, `/soleur:deepen-plan`, and `/soleur:work`
with an AC that read, verbatim:

> set an `~/.ssh/config` entry mapping `${SERVER_IP}` → `Hostname 127.0.0.1` +
> `Port 2222` + `User root` so the embedded Go SSH client in the TF
> provisioner block connects to the local TCP forward

The plan's Phase 3 §Research Insights confidently elaborated:

> The TF provisioner's embedded Go SSH client reads `~/.ssh/config` for
> the destination IP. Mapping `Host 135.181.45.178` → `Hostname 127.0.0.1`
> + `Port <P>` + `User root` + `IdentityFile ~/.ssh/...` causes the
> embedded client to dial `127.0.0.1:<P>`, where `cloudflared` is
> listening; cloudflared forwards over the tunnel...

**This is wrong.** Terraform's `provisioner "file"` / `provisioner
"remote-exec"` blocks use `golang.org/x/crypto/ssh` directly via the
internal `communicator/ssh` package. That package builds an
`ssh.ClientConfig` and calls `net.Dial("tcp", addr)` on the raw value of
`connection.host`. There is **no `~/.ssh/config` parser** in that code
path. Only the system `ssh` binary parses `~/.ssh/config`.

The bridge as designed would have shipped to prod, where the first
post-merge `apply-deploy-pipeline-fix.yml` run would have dialed
`SERVER_IP:22` directly (bypassing cloudflared on `127.0.0.1:2222`), hit
the Hetzner firewall's `var.admin_ips`-only ingress, and timed out with
the exact same `dial tcp 135.181.45.178:22: i/o timeout` the PR was
supposed to fix.

## Why deepen-plan didn't catch it

The plan's `deepen-plan` phase ran three gates (User-Brand Impact,
Observability, PAT-shape) and verified provider pins, lock files, and
DNS sibling patterns. It did NOT verify: **when a plan claims a
client-side configuration mechanism will affect a third-party library's
behavior, grep the actual library source (or its documented behavior)
to confirm the assumption.** The plan's own §Spec Gap section flagged
that terraform's provisioner *"uses the Go `golang.org/x/crypto/ssh`
client, NOT system `ssh`"* — but then proposed `~/.ssh/config` as the
fix anyway, conflating "the Go SSH client" with "any program that does
SSH" without checking whether that client actually reads the file.

## What caught it

Multi-agent post-implementation review.
**architecture-strategist** and **pattern-recognition-specialist**
independently flagged this as P1 (cross-reconciled by two orthogonal
agents):

- pattern-recognition labeled it **P1.1 "go-ssh client does NOT consult
  `~/.ssh/config`"** and traced the exact code path
  (`hashicorp/terraform/internal/communicator/ssh/`).
- architecture-strategist labeled it **"P1 — AC4 invariant ... `server.tf`
  unmodified ... load-bearing Go SSH client behavior"** and proposed
  three fix mechanisms (`/etc/hosts`, parameterized `server.tf`,
  `null_resource` + `local-exec`).

Neither the plan-time agents (research probes against `gh issue view`,
`grep` against `.terraform.lock.hcl`) nor the work-phase TDD gates
would have caught this — it's a third-party library behavior assumption,
not a code defect. The defect class is **plan-time empirical-probe
assumptions vs. actual caller surfaces** (already documented in
`knowledge-base/project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md`
under a different domain): the plan's probe ran against
*human-operator SSH* (which DOES read `~/.ssh/config`) and over-
generalized to *terraform's embedded Go SSH client* (which does NOT).

## Solution

Replaced the `~/.ssh/config` mechanism with an `iptables -t nat OUTPUT
REDIRECT` rule on the runner:

```bash
sudo iptables -t nat -A OUTPUT \
  -d "$SERVER_IP" -p tcp --dport 22 \
  -j REDIRECT --to-ports 2222
```

Kernel NAT redirect is transparent to userspace — the Go SSH client
dials `SERVER_IP:22`, the kernel rewrites the destination to
`127.0.0.1:2222` where cloudflared listens. No `server.tf` modification
required (preserves AC4 invariant). Paired with an `if: always()`
teardown step that removes the rule.

`/etc/hosts` was considered first but rejected: `/etc/hosts` maps
hostnames to IPs, NOT IPs to other IPs. terraform's `connection.host`
expands to the literal `hcloud_server.web.ipv4_address` (a string like
`135.181.45.178`), so `/etc/hosts` cannot remap it.

## Key Insight

When a plan proposes a **client-side configuration mechanism** (env
var, dotfile, command-line flag, registry entry) that depends on a
third-party library/binary reading that mechanism, the plan MUST grep
or otherwise confirm the actual library reads that source. The
inversion is common because "every SSH client reads `~/.ssh/config`" is
folk wisdom — true for OpenSSH-derived binaries, false for many
language-native clients (`golang.org/x/crypto/ssh`, Python's
`paramiko`, Rust's `russh`, Java's `JSch`/`SSHJ`). The same class
applies to `npm` vs `package-lock.json`-only loaders, `git` vs
`libgit2`-based tools, and any "the X client reads Y" assertion.

**Plan-time gate to add:** when a plan instructs operator/CI to write
a config file (`~/.ssh/config`, `~/.gitconfig`, `~/.npmrc`,
`/etc/hosts`, registry keys, environment files) AND the consumer is
**not** the system binary of the same name, grep the consumer's source
or docs for the read path. If unverified, escalate to a research probe
before signing off on the plan.

## Prevention

1. **Plan §Sharp Edges should include a "client-side config mechanism"
   item** — "When this plan claims `<file>` will be read by
   `<consumer>`, name the read path or cite the consumer's docs." If
   the plan can't, refuse to ship the mechanism.

2. **Multi-agent post-implementation review remains the load-bearing
   safety net** for this defect class. Two independent orthogonal
   agents flagged this in PR #4181's review batch — neither the work
   phase's RED/GREEN nor terraform validate/fmt nor actionlint would
   have caught it (the workflow is well-formed YAML; the bug is
   semantic). Per
   `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`,
   this is a textbook "Feature-wiring composition bug" — module A
   (cloudflared local forward) is correct, module B (`~/.ssh/config`
   rewrite) is correct in isolation, but A+B together violate the
   invariant that lives in module C (terraform's Go SSH client's read
   path) that the plan never inspected.

3. **AC verification commands must be RUN at /work time**, not
   rubber-stamped. PR #4181's plan AC1 claimed
   `grep -c 'cloudflare_zero_trust_access_application' tunnel.tf` returns
   `2`; actual returned `4` (counts both `resource` declarations AND
   `application_id =` references in policy resources). AC5 similarly
   drifted (1 vs 2). The verification commands were under-specified
   greps that were never executed before marking AC `[x]`. Adopt:
   verification commands appear with `expected: <N>` AND `/work` runs
   each one before marking the AC done.

## Session Errors

1. **Plan's `~/.ssh/config` mechanism is load-bearing-incorrect** —
   Recovery: replaced with `iptables -t nat OUTPUT REDIRECT` on the
   runner (transparent to the Go SSH client). Prevention: add a Sharp
   Edges item to `/soleur:plan` and `/soleur:deepen-plan` requiring
   client-side-config mechanisms to cite the consumer's documented
   read path.

2. **Plan AC verification greps rubber-stamped, not run** — AC1 claimed
   grep returns 2 (actual: 4); AC5 claimed 1 (actual: 2). Recovery:
   updated greps to be more specific (anchored to `^resource`) and
   re-ran them. Prevention: `/soleur:work` should execute each AC's
   verification command before marking `[x]`, comparing actual vs
   expected.

3. **Plan cited a non-existent precedent file** —
   `apps/web-platform/infra/scripts/get-app-installation-id.sh` does
   not exist; plan §AC7 referenced it as the sync-script precedent.
   Recovery: patterned the new script against
   `scripts/rotate-x-api-secret-bootstrap.sh`. Prevention:
   `/soleur:plan` should `ls` cited precedent paths before writing
   them into ACs.

4. **Initial `sed` over-marked plan checkboxes** — bulk-marked AC1-AC16
   `[x]` including post-merge ACs (AC13-AC16) that hadn't run.
   Recovery: counter-sed scoped to `AC1[3-6]` reverted them
   immediately. Prevention: split pre-merge and post-merge AC marking
   into two explicit sed passes with line-range scoping.

5. **Shellcheck SC2015 info on `(cd X && cmd || true)` pattern** —
   shellcheck warned the pattern is ambiguous. Recovery: switched to
   `pushd X; cmd || true; popd`. Prevention: prefer `pushd/popd` over
   inline `cd X && ...` in scripts where shellcheck runs.

6. **PreToolUse `security_reminder_hook.py` advisory** blocked the
   first Edit attempts on `.github/workflows/*.yml`. Recovery: retry
   succeeded (it's advisory, not a hard deny). Prevention: none
   needed; the hook is doing its job (reminding about workflow-inject
   patterns) and the second attempt was authorized by the operator
   gate.

## Related

- PR #4181 (review fixes commit `17e433a8`)
- Issue #4177 (the CI→host SSH timeout root issue)
- PR #4165 / #4144 (PAT→GitHub App migration that unmasked the SSH gap)
- #749 (original CF Tunnel deploy architectural decision)
- [[2026-04-15-multi-agent-review-catches-bugs-tests-miss]] — "Feature-wiring
  composition bug" class
- [[2026-05-18-supabase-custom-access-token-hook-discriminator]] — same
  class: plan-time empirical-probe assumptions vs. actual caller
  surfaces
- [[2026-05-12-plan-precondition-and-3-value-enum-gate-drift]] — same
  class: review prompts must enumerate the full surface, not echo the
  plan's single-value framing
