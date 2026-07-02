---
name: multi-host-ga-cutover-review-mechanisms
description: Four non-obvious traps caught by the 3.D GA-cutover review set — Hetzner private-net firewall bypass, Sentry feature/op tag detector-mismatch, remote-store fetch data-loss, and LUKS additive-mount re-point stranding
metadata:
  type: project
  issue: 5274
  pr: 3.D
  tags: [multi-host, cutover, security, observability, data-integrity, hetzner, luks, git-data]
---

# Multi-host GA cutover (#5274 Sub-PR 3.D) — review-caught mechanisms

Six-agent review (security-sentinel, data-integrity-guardian, observability-coverage,
deployment-verification, user-impact + a CTO ruling) of the dark-launched GA-cutover PR
caught four production-severity traps that all passed `tsc`, unit tests, and `terraform
validate`. Each is generalizable.

## 1. Hetzner cloud firewalls do NOT filter the private net → port-scoping must be guest-side

`hcloud_firewall` rules apply only to the **public** interface; intra-`hcloud_network`
(`10.0.1.0/24`) traffic is open by network membership (the codebase says so at
`git-data.tf:182-186`). So "scope port 8443 to peer hosts with an `hcloud_firewall` rule"
is a **non-functional** fix — the attack traverses the private net the firewall never sees.
A token-less private-net listener (the owner session-proxy) was therefore reachable from
*any* `10.0.1.x` host, including the deliberately-lesser-privileged git-data host →
full account takeover via `attachProxiedSession`. **Fix pattern:** enforce peer-origin at
the **application layer** (guest-side) — reject any connection whose `req.socket.remoteAddress`
(normalize the `::ffff:` v4-mapped prefix) is not in an allowlist of peer private IPs,
**fail-closed** (no allowlist while the listener would otherwise start ⇒ refuse to start).
Unit-testable; no PKI. mTLS is the wrong tool when both legit peers already hold the cert.

## 2. Observability detector-mismatch: query the tag namespace the EMISSION sets, not the one you assume

A GA-gating soak script + operator runbook queried Sentry `op:worktree_lease OR
op:control_plane_route OR (op:git-data member:false)`. But `reportSilentFallback` maps
`feature → tag feature` and `op → tag op` (`observability.ts`); every emission set those
three classes as the **`feature`** tag (with `op` a *sub*-operation), `member:false` lives
in **non-searchable `extra`**, and the cross-tenant denial is **`warnSilentFallback`
(level:warning)**. So all three disjuncts matched **zero** events → the soak **always
exits PASS** → it would have flipped ADR-068 `adopting→accepted` and closed the epic
*during a live regression*. A gate that can only ever report healthy is worse than no gate.
**Prevention:** when writing an alert/soak query, grep the actual emission sites for the
literal tag keys + level + whether the field is a searchable tag vs `extra`; never mirror a
precedent query's tag namespace without re-deriving it against the code that emits.

## 3. Clone-from-remote-store: fetch into remote-tracking refs + guarded reset on the fresh-graft path ONLY

Wiring a shared-store fetch (`fetchFromGitData`) as a rehydration read-source was
structurally blocked: the primitive mapped `+…:refs/heads/*`, but the destination is a
**live checked-out branch** (`git clone --depth 1`), so a force-fetch either refuses or
silently discards local-only commits. CTO ruling: map into **`refs/remotes/git-data/*`**
(a remote-tracking namespace git can never refuse and can never overwrite a checked-out
branch), then `git reset --hard refs/remotes/git-data/<primary>` **only on the fresh-graft
path** — reachable solely past the `isValidGitWorkTree` early-return, so by construction
zero local-only commits exist at the reset point (prove it with a live-worktree negative
test asserting neither fetch nor reset runs). Also: the shared store ⊇ GitHub origin here
(the per-turn replicator force-pushes ALL refs; the GitHub path auto-commits only a
subset), so rehydration = `clone(GitHub) → overlay(store)`, and rollback loses store-only
writes — state that dependency explicitly.

## 4. LUKS/volume cutover: an additive mount + "terraform re-points it" is a data-stranding trap

The cutover mounted the fresh LUKS volume **additively** at `/mnt/git-data-luks` while
every host write path hardcodes `/mnt/git-data/repositories`, and the "terraform re-points
the git-data mount to the LUKS volume" claim was **unbacked prose** — no resource,
cloud-init directive, or script step did it. Result: post-flip every push lands on the
**plaintext** volume (LUKS silently unmet, health stays green), the LUKS copy drifts stale,
and the `rm -rf` decommission destroys **live** data. Two corollaries: (a) cloud-init runs
**only on first boot**, so `terraform apply` attaching a volume to a *running* host never
mounts it — the cutover script must `luksOpen`+mount idempotently itself; (b) the
**write-freeze must actually block writers** — a `touch .freeze` sentinel is a no-op unless
the pre-receive hook honors it, and the identity-verify must run **post-drain** or it races
live writers. **Fix pattern:** a scripted `repoint` step during the freeze (mount the
mapper at the canonical path + rewrite fstab so all hardcoded paths become encrypted-backed
with zero path changes) + a **canary** (assert the canonical path is backed by the mapper
device) that **gates** the destructive wipe.

## Process notes

- **`planTier:"free"` conservative default on session migration is a wrong-throttle, not a
  safe default:** a proxy-migrated *paid* user capped at free=1 for the ~60s until the first
  subscription-refresh tick (no leading tick) hard-closes on `start_session` with a spurious
  upgrade modal, and the Stripe rescue is unreachable if `stripeSubscriptionId` is unset.
  Hydrate real subscription state **inline before enabling the message handler**, not on a
  deferred tick. Coordinated drains make this a mass incident.
- **`hr-menu-option-ack-not-prod-write-auth` in practice:** an operator picking "drive the
  live cutover now" in an `AskUserQuestion` is *intent*, not authorization to power-cycle
  prod — and the cutover was physically **out of sequence** before merge+deploy anyway (the
  code it depends on isn't live). The right move was to build the full automation + one-command
  runbook and keep the apply operator-gated post-merge.

## Session Errors

1. **Corrupted `/work` resume prompt** — the args were garbled; built on the plan file + live
   code instead. **Prevention:** treat a corrupted/garbled prompt as UNVERIFIED and re-derive
   state from authoritative sources (already the "verify, don't trust" posture).
2. **Bash CWD persisted to `apps/web-platform`**, breaking repo-root-relative paths.
   **Prevention:** use absolute paths from inside a worktree (already a rule/learning).
3. **Over-broad `old_string` dropped the adjacent NFR-027 block** during an NFR-026 edit;
   caught by a follow-up structural grep and restored. **Prevention:** scope `old_string` to
   the target block; grep the surrounding headings after a multi-line edit.
4. **`check-tc-document-sha.sh` false-failed from the wrong CWD** (globbed 0 docs); passed from
   repo root. **Prevention:** run repo-root-scoped gates from the repo root.
5. **Full-suite parallel-load flakes** (14 RTL component tests) — passed in isolation.
   **Prevention:** re-run failed UI files in isolation before treating as a regression (#5113).
6. **`gh issue create` blocked on `--milestone`** — body was pre-written to a file, retried
   cleanly. **Prevention:** write issue bodies to a file (not a same-command heredoc) so a
   hook denial doesn't take the body down with it (already a learning).
