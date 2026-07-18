---
title: "fix(infra): bring up the workspaces-luks cutover SSH bridge (Option C — bash-SSH, private-IP-consistent)"
type: fix
date: 2026-07-18
branch: feat-one-shot-cutover-bridge-bringup
lane: cross-domain
brand_survival_threshold: none
refs: ["#6649", "#6604", "#6680", "ADR-119", "ADR-114", "#4177", "#4844"]
---

# 🐛 fix(infra): bring up the workspaces-luks cutover SSH bridge (Option C)

## Overview

`workspaces-luks-cutover.yml -f dry_run=true` and `workspaces-luks-verify.yml` were authored
but have never run end-to-end. A dry_run-guard fix (merged earlier today) got the cutover as
far as the `CF Tunnel SSH bridge` step; the bridge then fails `terraform: command not found`
(exit 127), and two further walls sit behind it. This plan implements **Option C** from a
completed investigation: make the bridge a real bash-SSH bridge scoped to web-1, using the
**private-IP-consistent** path (`10.0.1.10` for both the iptables redirect scope and the SSH
target), so the #6649 dry-run escrow rehearsal can reach web-1 — while keeping the composite
action **backward-compatible** with the critical-path `apply-web-platform-infra.yml`.

The three walls (all verified this session):

1. **`terraform: command not found` (exit 127).** `.github/actions/cf-tunnel-ssh-bridge/action.yml:165`
   runs `terraform output -raw server_ip`, but neither `workspaces-luks-cutover.yml` nor
   `workspaces-luks-verify.yml` installs terraform (`grep -c setup-terraform|terraform` = 0 in both).
2. **SERVER_IP vs WEB_HOST mismatch.** The bridge scopes `iptables -t nat -A OUTPUT -d "$SERVER_IP"`
   to web-1's **public** IP (`terraform output server_ip` = `hcloud_server.web["web-1"].ipv4_address`,
   `outputs.tf:3`), but the cutover Run step dials the **private** IP (`WEB_HOST: "10.0.1.10"`,
   cutover `:102`). The redirect never catches the SSH.
3. **`WEB_HOST_SSH` never set.** The bridge never exports `WEB_HOST_SSH`/`GIT_DATA_SSH` and never
   writes an SSH keyfile (five comments falsely claim it does — action header `:55-57`, verify `:59`,
   git-data `:12-13`, `:109`). Bare `ssh "$WEB_HOST"` has no `-i` key and no `root@` user, so it
   would fail even if the redirect caught it.

**Why the private-IP path works (design decision — see Research Reconciliation).** The iptables
`-d` scope is only a *runner-side hijack filter*: whatever destination it matches is redirected
pre-egress to `127.0.0.1:2222`, which cloudflared forwards over the tunnel to the ingress rule
`ssh.${app_domain_base}` → `ssh://${web_hosts["web-1"].private_ip}:22` = `ssh://10.0.1.10:22`
(`tunnel.tf:69-72`, `variables.tf:110`). So scoping `-d 10.0.1.10` catches the cutover's
`ssh 10.0.1.10`, redirects it before egress (the private IP need not be routable from the runner),
and the tunnel always lands on web-1. This makes `server-ip == WEB_HOST == 10.0.1.10` internally
consistent and **eliminates terraform entirely** from the cutover/verify path.

## Research Reconciliation — Spec vs. Codebase

| Claim (from task background) | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| Bridge exits 127 (`terraform: command not found`) | Confirmed: cutover/verify install no terraform; action.yml:165 calls `terraform output` | Add optional `server-ip`; when set, skip `terraform output` verbatim |
| Redirect scopes public IP; Run step dials private `10.0.1.10` | Confirmed: outputs.tf:3 = public `ipv4_address`; cutover:102 `WEB_HOST: "10.0.1.10"` | Pass `server-ip: "10.0.1.10"` = WEB_HOST → redirect scope matches the dialed IP |
| Bridge never exports `WEB_HOST_SSH`, no keyfile; 5 false comments | Confirmed: action.yml exports only SERVER_IP/CLOUDFLARED_PID/TF_VAR_ci_ssh_private_key/TUNNEL_SERVICE_TOKEN_* (`:55-57`); verify:59 falsely says "key + ProxyCommand" | Write DEPLOY_SSH_PRIVATE_KEY to chmod-600 keyfile; export `WEB_HOST_SSH`/`GIT_DATA_SSH`/`CI_SSH_KEYFILE`; correct the comments |
| DEPLOY_SSH_PRIVATE_KEY authenticates as root@web-1 | Confirmed: ci-ssh-key.tf — DEPLOY_SSH_PRIVATE_KEY = `tls_private_key.ci_ssh`; public half appended to root's authorized_keys; server.tf connections use `user="root"` | `WEB_HOST_SSH = ssh -i <keyfile> … -l root` |
| RECOMMENDED: use private IP `10.0.1.10` for both, avoid terraform | Confirmed against tunnel.tf:69-72 (origin-relative `ssh://10.0.1.10:22`, ADR-114 I2) + variables.tf:110 (`private_ip = "10.0.1.10"`) + model.c4:380 | **ADOPTED — private-10.0.1.10-consistent.** No public-IP-via-Doppler fallback needed |
| Tunnel might need the **public** IP as redirect target | FALSE — tunnel.tf:66-68 ("the runner still dials the public SERVER_IP" is the *apply* path only); the tunnel host-side always delivers to web-1 private:22 regardless of the `-d` scope | Fallback (public-IP-via-Doppler) NOT needed; documented as rejected alternative |

**Premise Validation (Phase 0.6):** #6649 is OPEN (do NOT close — closure is gated on a
post-merge green `dry_run=true` rehearsal). #6680 is OPEN (git-data 10.0.1.20 reach is a separate
architectural gap — out of scope). Both recent cutover runs (29644526137, 29649845529) failed,
confirming the workflow has never run end-to-end. Cited files (action.yml, tunnel.tf, outputs.tf,
variables.tf, ci-ssh-key.tf, server.tf, the two `.test.sh`) all exist on the branch and match the
task's descriptions.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing directly — a broken bridge
means the `dry_run=true` escrow rehearsal cannot reach web-1, so #6649 stays open and the
LUKS-at-rest cutover remains un-rehearsed. `dry_run=true` performs **no freeze and no repoint**
(the escrow probe runs before the `DRY_RUN != 1` gate; workspaces-cutover.sh), so no sole-copy user
data is touched by this change.
**If this leaks, the user's data is exposed via:** the CI SSH private key. It is already in Doppler
`prd_terraform` and already loaded into `$GITHUB_ENV` (`TF_VAR_ci_ssh_private_key`) by the action;
this change additionally writes it to a **chmod-600** tempfile that the `if: always()` teardown
**shreds**, and every key line is `::add-mask::`ed (existing decode step). No new exposure surface
beyond the already-handled key.
**Brand-survival threshold:** none — reason: this change only brings up the SSH bridge for the
non-mutating `dry_run=true` rehearsal + the read-only verify workflow; the destructive freeze is a
separate, environment-gated dispatch that this PR does not run. (Scope-out bullet for the
`.github/**` sensitive-path gate: `threshold: none, reason: dry-run/verify only — no sole-copy data
mutation in this change`.)

## Files to Edit

- `.github/actions/cf-tunnel-ssh-bridge/action.yml`
  - Add **optional** input `server-ip` (`required: false`, default `''`).
  - In the "Start cloudflared SSH bridge + iptables NAT redirect" step: add
    `SERVER_IP_INPUT: ${{ inputs.server-ip }}` to `env:`; replace the bare
    `SERVER_IP=$(terraform output -raw server_ip)` with a guard — **use `$SERVER_IP_INPUT` when
    non-empty, otherwise keep the `terraform output -raw server_ip` path verbatim** (including the
    empty-check + `::error::`). The terraform branch must remain byte-identical for callers that do
    not pass `server-ip`.
  - In the "Decode CI SSH private key into TF_VAR_ci_ssh_private_key" step (where `$KEY` is in
    scope): after the existing heredoc write, **also** write `$KEY` to a chmod-600 keyfile
    (`KEYFILE=$(mktemp); chmod 600 "$KEYFILE"; printf '%s\n' "$KEY" > "$KEYFILE"`) and export to
    `$GITHUB_ENV`: `CI_SSH_KEYFILE=$KEYFILE`, and both
    `WEB_HOST_SSH` and `GIT_DATA_SSH` = `ssh -i $KEYFILE -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root`.
    These additions are **inert** for terraform callers (unused env + unused file). Broaden the
    step name to reflect the added keyfile/export.
  - Correct the five false comments (action header OUTPUTS/PREREQUISITES `:48-57`, and the caller
    comments) to state reality: the bridge now writes an SSH keyfile and exports
    `WEB_HOST_SSH`/`GIT_DATA_SSH`; the mechanism is **key + iptables NAT redirect (NOT a
    ProxyCommand)**; `terraform init` is required **only** when `server-ip` is unset.
- `.github/workflows/workspaces-luks-cutover.yml`
  - Pass `server-ip: "10.0.1.10"` to the `CF Tunnel SSH bridge` step (matches the Run step's
    `WEB_HOST: "10.0.1.10"`).
  - Add an `if: always()` teardown step **after** "Run workspaces-luks cutover": delete the NAT
    rule scoped to `$SERVER_IP`, kill `$CLOUDFLARED_PID`, **shred `$CI_SSH_KEYFILE`**, and dump
    `/tmp/cloudflared.log` — all `-n`/`-f` guarded (modeled on `apply-web-platform-infra.yml:801-823`).
- `.github/workflows/workspaces-luks-verify.yml`
  - Identical bridge treatment: pass `server-ip: "10.0.1.10"`; add the same `if: always()`
    teardown (NAT delete + cloudflared kill + shred keyfile + log dump). Fix the `:59` comment
    ("key + ProxyCommand" → "key + iptables NAT redirect").

## Files NOT to edit (assert unchanged)

- `.github/workflows/apply-web-platform-infra.yml` — critical path. It calls the bridge **without**
  `server-ip` (`:649-656`), so the optional input defaults empty → the terraform path runs verbatim.
  The keyfile-write + `WEB_HOST_SSH`/`GIT_DATA_SSH` export are inert (terraform's Go SSH client uses
  `TF_VAR_ci_ssh_private_key` + the NAT redirect, not these env vars). **AC: `git diff origin/main`
  on this file is empty.**
- `.github/workflows/git-data-cutover.yml` — untouched (#6680). It also calls the bridge without
  `server-ip` (terraform path) and dials `10.0.1.20`; the bridge additions newly export
  `WEB_HOST_SSH`/`GIT_DATA_SSH` for it, but its 10.0.1.20 host has no tunnel ingress and no NAT
  redirect, so #6680 remains exactly as-is — this change neither fixes nor breaks it.
- `.github/workflows/apply-deploy-pipeline-fix.yml` — calls the bridge without `server-ip`
  (terraform path); additions inert.

## Implementation Phases

**Phase 0 — Preconditions (verify, do not code).**
- Re-confirm `web_hosts["web-1"].private_ip == "10.0.1.10"` (`variables.tf:110`) and tunnel ingress
  `ssh://…private_ip:22` (`tunnel.tf:69-72`).
- Confirm `git diff origin/main --stat` touches only the three target files.

**Phase 1 — Composite action: optional `server-ip` (removes wall #1 + #2).**
- Add the input; guard the terraform output behind `[[ -z "$SERVER_IP_INPUT" ]]`.
- Contract-first: this phase changes the SERVER_IP source; it must land before the callers pass the
  new input (they already dial 10.0.1.10, so no dead code — but keep the action edit first).

**Phase 2 — Composite action: keyfile + `WEB_HOST_SSH`/`GIT_DATA_SSH` export (removes wall #3).**
- Extend the decode step; export the three env vars. Verify inertness for terraform callers by
  reasoning (no consumer of these env vars in apply/pipeline-fix).

**Phase 3 — Cutover + verify workflows: pass `server-ip` + add teardown.**
- Add `server-ip: "10.0.1.10"` to both bridge invocations.
- Add the `if: always()` teardown (shred keyfile + bridge teardown) to both.
- Fix the verify `:59` comment.

**Phase 4 — Verify (see Verification).**

## Acceptance Criteria

### Pre-merge (PR)
1. `action.yml` declares `server-ip` with `required: false` — `grep -A3 'server-ip:' action.yml`
   shows `required: false`.
2. The `terraform output -raw server_ip` line is guarded so it runs **only** when `server-ip` is
   empty — `grep -B2 'terraform output -raw server_ip' action.yml` shows the `[[ -z "$SERVER_IP_INPUT" ]]` guard.
3. The bridge writes a chmod-600 keyfile and exports `WEB_HOST_SSH`, `GIT_DATA_SSH`, `CI_SSH_KEYFILE`
   to `$GITHUB_ENV`, with the value `ssh -i <keyfile> -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -l root`.
4. `workspaces-luks-cutover.yml` and `workspaces-luks-verify.yml` each pass `server-ip: "10.0.1.10"`
   to the bridge, and the value equals each workflow's `WEB_HOST`.
5. Both cutover and verify have an `if: always()` teardown that (a) `iptables -t nat -D OUTPUT -d "$SERVER_IP" …`,
   (b) kills `$CLOUDFLARED_PID`, (c) shreds `$CI_SSH_KEYFILE` — each `-n`/`-f` guarded.
6. `git diff origin/main -- .github/workflows/apply-web-platform-infra.yml` is **empty** (byte-unchanged bridge invocation).
7. `git diff origin/main -- .github/workflows/git-data-cutover.yml` is **empty**.
8. `actionlint` is clean on `workspaces-luks-cutover.yml`, `workspaces-luks-verify.yml`, and (schema-permitting) the composite `action.yml` is validated by extracting each `run:` snippet through `bash -n`/`bash -c` (actionlint does NOT validate composite-action files — do not run it on `action.yml`; extract + shellcheck the shell instead).
9. `bash apps/web-platform/infra/workspaces-luks-header.test.sh` passes (H7 stays green — no AWS creds appear in the edited cutover workflow).
10. `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh` passes (concurrency groups untouched).
11. No `terraform`/`terraform output` token appears in the cutover/verify execution path — `grep -c 'terraform' .github/workflows/workspaces-luks-{cutover,verify}.yml` = 0.
12. The five false comments (action `:55-57`, verify `:59`, and the OUTPUTS/PREREQUISITES header) are corrected to describe key+keyfile+NAT-redirect reality.
13. PR body uses `Ref #6649` (NOT `Closes #6649`) — closure is soak/rehearsal-gated post-merge.

### Post-merge (operator — dispatch automatable, approval is the sole human gate)
- Dispatch the rehearsal: `gh workflow run workspaces-luks-cutover.yml -f dry_run=true -f confirm=CUTOVER-WORKSPACES-LUKS`
  (automatable via `gh`; `/soleur:ship` can fire it). **Automation: not feasible past the
  `environment: workspaces-luks-cutover` required-reviewer approval** — a named human authorization
  gate on a sole-copy-data workflow (`playwright-attempt: N/A — GitHub environment approval is a
  first-class human gate, not a dashboard form`).
- After approval, read the run log (NO ssh): `gh run view <id> --log` — confirm the `CF Tunnel SSH
  bridge` step is green (no exit 127) and the escrow probe emits its GREEN signal. This is the
  #6649 closure evidence; close #6649 only after this passes.

## Observability

```yaml
liveness_signal:
  what: dry_run=true rehearsal reaches the escrow probe (GREEN escrow signal) before the DRY_RUN freeze gate
  cadence: on workflow_dispatch (rehearsal), not scheduled
  alert_target: GitHub Actions run status + step summary
  configured_in: workspaces-luks-cutover.yml (Cutover summary step) + workspaces-cutover.sh escrow_probe
error_reporting:
  destination: GitHub Actions `::error::` annotations (bridge steps) + /tmp/cloudflared.log dump (teardown) + Sentry (feature=workspaces-luks op=workspaces-luks-drift) for script-side failures
  fail_loud: yes — every bridge step exits non-zero with an `::error::`; the Run step surfaces the ssh rc
failure_modes:
  - mode: cloudflared TCP forward does not open on 127.0.0.1:2222
    detection: `::error::` "cloudflared TCP forward did not open …" + log dump
    alert_route: run failure + teardown log
  - mode: SSH auth/connect fails (wrong key/user/redirect scope)
    detection: Run step ssh rc != 0 → `::error::` (cutover) / probe_rc (verify)
    alert_route: run failure
  - mode: iptables NAT redirect insertion fails
    detection: `::error::` "iptables NAT redirect … failed"
    alert_route: run failure
logs:
  where: GitHub Actions run log + /tmp/cloudflared.log (dumped by teardown)
  retention: GitHub Actions default (90d)
discoverability_test:
  command: gh run view <run-id> --log   # NO ssh
  expected_output: "CF Tunnel SSH bridge" step green (no exit 127) AND escrow probe GREEN
```

## Hypotheses (Phase 1.4 — SSH/firewall/terraform; L3→L7 order)

Per `hr-ssh-diagnosis-verify-firewall`, verify L3 (firewall/routing) before L7 (sshd/service):

- **L3 firewall/egress:** the GH runner egress IP is NOT in `var.admin_ips` (by design — 5000+
  rotating IPs) and cannot be. This is the reason the tunnel bridge exists. The private `10.0.1.10`
  need not be routable from the runner because the iptables OUTPUT REDIRECT rewrites the destination
  **before egress**. ✔ verified against tunnel.tf + the action's existing NAT rule.
- **L3/L4 NAT redirect:** `-d 10.0.1.10 --dport 22 → 127.0.0.1:2222` catches the cutover's
  `ssh 10.0.1.10`. ✔ this is precisely what wall #2 fixes (scope was the public IP).
- **L4/L7 tunnel:** cloudflared `127.0.0.1:2222` → CF Access (ci_ssh service token) → ingress
  `ssh.${app_domain_base}` → `ssh://10.0.1.10:22`. ✔ tunnel.tf:69-72 (origin-relative, ADR-114 I2).
- **L7 sshd auth:** `-i <keyfile with DEPLOY_SSH_PRIVATE_KEY> -l root` — public half is in web-1
  root's `authorized_keys` (ci-ssh-key.tf). ✔ this is what wall #3 fixes.

The three walls are exactly the L3→L7 failure chain, addressed in order: terraform 127 (removed by
`server-ip`), redirect-scope mismatch (fixed by `server-ip == WEB_HOST == 10.0.1.10`), missing
key/user (fixed by the keyfile + `WEB_HOST_SSH` export).

## Domain Review

**Domains relevant:** Engineering (infra/CI/security). Product: none (no UI surface — Files to Edit
are `.github/**` only; no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx`).

### Engineering / Security
**Status:** reviewed (inline)
**Assessment:** The one security-relevant addition is writing the CI SSH private key to disk. It is
mitigated: the key is already in `$GITHUB_ENV`; the keyfile is chmod-600 (mktemp default), every
line is `::add-mask::`ed by the existing decode step, and the `if: always()` teardown shreds it.
`server-ip` is a static literal (`"10.0.1.10"`), not attacker-controlled. No new secret, vendor, or
host is introduced. `StrictHostKeyChecking=accept-new` + `UserKnownHostsFile=/dev/null` is the
established CI pattern for an ephemeral runner reaching a host over a CF-Access-gated tunnel (the
edge already authenticates via the service token; TOFU on the inner hop adds no meaningful risk on a
one-shot ephemeral runner).

### Product/UX Gate
**Tier:** none — no user-facing surface.

## Infrastructure (IaC)

**Skip — no new infrastructure.** This plan edits a composite action + two workflows and consumes
**existing** provisioned infrastructure: the Cloudflare Tunnel + CF Access ci_ssh service token
(tunnel.tf), the CI SSH keypair + Doppler `DEPLOY_SSH_PRIVATE_KEY` (ci-ssh-key.tf), and web-1's
root authorized_keys. No `*.tf` file changes; no server/service/secret/vendor is created. The
entire point of Option C is to **remove** the terraform dependency from the cutover/verify path.

## Architecture Decision (ADR/C4)

**No new ADR; no C4 change.** This implements "Option C" within the existing bridge architecture
(#4177/#4844 composite action) under ADR-119 (workspaces-luks cutover) and ADR-114 (origin-relative
tunnel ingress, I2). No ADR is reversed or extended: the tunnel topology is unchanged and is
exactly what makes the private-IP path correct.

**C4 completeness check (all three `.c4` files read):** the relevant elements are already modeled —
`model.c4:386 github -> tunnel` ("CI … reaches web-1's shell … via CF Access service tokens"),
`model.c4:380 tunnel -> hetzner` ("ssh. → ssh://10.0.1.10:22 — ORIGIN-RELATIVE"), and the tunnel
container itself (`model.c4:176-178`); `views.c4:32` includes the tunnel. **External actors**
(GitHub Actions runner = `github`), **external/edge systems** (Cloudflare tunnel = `tunnel`),
**containers/data-stores** (web-1 = `hetzner`, workspacesVolume), and the **access relationship**
(CI → tunnel → web-1 SSH) are all present. Option C adds only another *caller* (the cutover/verify
workflows) of the already-modeled `github -> tunnel` SSH edge — no new actor, system, store, or
access relationship. Therefore **no C4 impact**.

## Alternative Approaches Considered

| Alternative | Why rejected |
| --- | --- |
| **Public-IP-via-Doppler** (source web-1 public IP from a Doppler secret, set `server-ip` = public IP, match `WEB_HOST` = public IP) | Rejected. tunnel.tf:66-68's "runner still dials the public SERVER_IP" describes only the *apply* path; the tunnel host-side always delivers to web-1 private:22 regardless of the `-d` scope, so the public IP buys nothing and adds a Doppler read + a routable-IP assumption. The private-IP path is simpler and terraform-free. |
| **Install terraform in cutover/verify** (`setup-terraform` + `terraform init`) | Rejected. Re-introduces the R2-backend init + credentials into a workflow whose whole design (creds in GitHub secrets, nothing on the host) is meant to avoid it; `server-ip` removes the need. |
| **Modify git-data-cutover.yml to reach 10.0.1.20** | Out of scope — separate architectural gap tracked as #6680 (no tunnel ingress for the git-data host). |

## Open Code-Review Overlap

None — sweep of open `code-review`-labelled issues against the three Files-to-Edit returned no
matches (infra CI/action files; the open LUKS issues #6649/#6680 are feature/gap issues, not
code-review scope-outs on these files).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's threshold is `none` with a
  reason bullet.)
- `actionlint` MUST NOT be run against `.github/actions/cf-tunnel-ssh-bridge/action.yml` — it
  validates *workflows* (require `on:`/`jobs:`) and emits spurious "section missing" errors on the
  composite-action schema. Validate embedded `run:` shell via `bash -n`/`bash -c` + shellcheck
  instead (learning 2026-05-18-composite-action-extraction-inline-on-multi-file-rollout).
- The keyfile-write + `WEB_HOST_SSH`/`GIT_DATA_SSH` export run for **every** bridge caller; assert
  inertness for apply/pipeline-fix by confirming no caller consumes those env vars (grep returned
  hits only in cutover/verify/git-data).
- Do NOT `Closes #6649` — use `Ref #6649`; closure is gated on the post-merge green `dry_run=true`
  rehearsal (which requires the environment reviewer's approval).
