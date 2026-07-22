---
title: "A shared action's contract comments claimed exports it never produced; a never-run workflow reveals bring-up walls one at a time"
date: 2026-07-18
category: integration-issues
tags: [github-actions, composite-action, ssh, cf-tunnel, cutover, workspaces-luks, never-run-workflow, false-contract]
module: Web Platform Infrastructure
issue: 6649
---

# Shared-action false export-contract + never-run-workflow sequential walls

## Problem

Completing the #6649 LUKS-header escrow dry-run rehearsal meant bringing up the
`workspaces-luks-cutover.yml` workflow, which had been **authored but never run
end-to-end** (`Total runs 0`). Each fix revealed the next wall:

1. **Wall 1** (prior PR #6679): the `CF Tunnel SSH bridge` step was skipped on
   `dry_run=true` (an `if:` guard), so the SSH to web-1 timed out.
2. **Wall 2**: the bridge called `terraform output -raw server_ip` but the
   cutover workflow never installed terraform → `terraform: command not found`
   (exit 127).
3. **Wall 3**: the bridge action **never exported `WEB_HOST_SSH`** and never
   wrote an SSH keyfile — yet **five comments** across `git-data-cutover.yml`,
   `workspaces-luks-verify.yml`, and `git-data-cutover.sh` asserted "the bridge
   exports WEB_HOST_SSH/GIT_DATA_SSH as the exact ssh invocation." The cutover
   scripts consumed `${WEB_HOST_SSH:-ssh}`, so the unset var **silently degraded
   to a keyless bare `ssh`** as the runner user — which would fail auth
   confusingly rather than loudly.

## Key insights

### 1. A shared action's contract comments are aspirational until the code proves them.
The `cf-tunnel-ssh-bridge` action was extracted (PR #4845) as **terraform-only**
(exports `TF_VAR_ci_ssh_private_key` for terraform's Go SSH client). The
bash-ssh callers were added later and their comments described a `WEB_HOST_SSH`
export that the action **never actually made**. The `${WEB_HOST_SSH:-ssh}`
fallback masked the gap: no error, just a wrong (keyless) connection. **When a
caller reads `${X:-default}` for a value a shared action is *supposed* to
export, grep the action for the actual `>> "$GITHUB_ENV"` write — a fallback is
where a never-satisfied contract hides.** The fix here made the export real
(gated on a new `server-ip` input) AND dropped the `:-ssh` fallback so a missing
export fails loud.

### 2. A never-run workflow reveals bring-up walls sequentially — budget for the chain, not the first error.
`terraform: command not found` was only the *first observable* failure once the
bridge ran. Behind it: no server_ip source without terraform, then no keyfile,
then a public-vs-private-IP redirect mismatch. Fixing one exposes the next. For
a workflow with `Total runs 0`, treat the first green-to-red transition as the
start of a chain and trace the full path (here: read the working reference
`apply-web-platform-infra.yml`'s entire bridge preamble) before estimating scope.

### 3. Backward-compat for a shared action = a gated, default-inert new path.
The fix added an optional `server-ip` input. When empty (the terraform callers,
incl. the critical `apply-web-platform-infra.yml`), the terraform-output read +
`TF_VAR` export run exactly as before (byte-equivalent diff on that file); when
set, the terraform read is skipped and a keyfile + `WEB_HOST_SSH` export replace
it. Gating BOTH the new key form AND the old one into a mutually-exclusive
`if/else` keeps the private key off `$GITHUB_ENV` for the caller class that
doesn't need it (security-sentinel P3).

### 4. server-ip == the-host-the-script-dials is the load-bearing invariant.
The iptables `-d "$SERVER_IP"` NAT redirect must scope to the SAME address the
Run step SSHes to (both `10.0.1.10`), or the redirect misses the SSH. The tunnel
ingress (`tunnel.tf`) always lands on web-1 regardless of the dialed IP, so the
private IP works and needs no terraform. Single-source the literal (one env var)
so the two sites can't drift (architecture P3).

## Session errors (secondary)

- **SC2015 in copied teardown.** `[[ -f log ]] && tail … || true` (A && B || C)
  trips actionlint's shellcheck. Fixed to `if [[ -f log ]]; then tail … || true;
  fi` in both workflows AND the action-header exemplar callers copy. **Prevention:**
  when copying a teardown block from a contract comment, run actionlint on the
  result; fix the exemplar too so the next caller copies the clean form.
- **A bare-token AC grep (`grep -c terraform = 0`) tripped on my explanatory
  comment** containing the word "terraform." Reworded the comments. **Prevention:**
  a bare-token verification grep and prose that names the token collide — either
  anchor the AC on the syntactic construct (`hashicorp/setup-terraform`,
  `terraform output`) or keep the token out of comments (`cq-assert-anchor-not-bare-token`).

## Related

- Sequel to `2026-07-18-cutover-bridge-dryrun-guard-and-workflow-step-vs-in-script-ssh.md` (wall 1 + workflow-step-vs-in-script SSH).
- git-data-cutover's second-host (10.0.1.20) reach is a separate tunnel-ingress gap: #6680.
