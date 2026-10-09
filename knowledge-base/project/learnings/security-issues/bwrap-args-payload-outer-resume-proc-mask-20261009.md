---
title: 'bwrap --args payload parse semantics: masks must land at the outer setup end, never inside a payload'
date: 2026-10-09
category: engineering
tags: [bwrap, sandbox, procfs, argv-rewrite, security-boundary, cross-tenant]
symptoms: [Vendored CLI tail-appends --bind /proc /proc over the denyRead --tmpfs /proc, exposing host procfs inside the agent sandbox, /proc/<pid>/environ credential leak]
module: WebPlatform
component: agent-sandbox
problem_type: security_issue
resolution_type: code_fix
root_cause: argv_ordering
severity: high
---

# bwrap --args Payload Parse Semantics: Masks Land at the Outer Setup End

## Problem

Three issues in one cluster (#9723, #9725, #9558), all in `apps/web-platform/server/` + `infra/`:

1. **#9723** — the vendored CLI 2.1.284 builder's `enableWeakerNestedSandbox` appends
   `--bind /proc /proc` as the LAST setup token, re-mounting the container's real
   procfs over the denyRead `--tmpfs /proc`. Later mounts win: in-sandbox `/proc`
   showed every container process and same-uid `/proc/<pid>/environ` leaked
   `GIT_INSTALLATION_TOKEN` and session env.
2. **#9725** — after the ADR-068 git-data cutover, `workspacePathForWorkspaceId`
   resolves under `WORKTREE_ROOT` (`/var/lib/soleur/worktrees`) while
   `buildAgentSandboxConfig` only denied `WORKSPACES_ROOT`.
3. **#9558** — support-persona dispatch still minted GitHub installation tokens,
   wrote `.soleur-askpass.sh`, cloned, and opened GitHub egress for a persona
   whose sandbox is `sandboxWrite: "none"`.

## Solution

- **#9723:** `infra/bwrap-shim/bwrap` (PATH shim over `/usr/bin/bwrap`) splices
  `--proc /proc` at the LAST setup position of the merged argv — outer `--`,
  else outer operand, else argv tail — so a fresh pidns-scoped procfs mounts
  over the vendor tail bind. `--proc` not `--tmpfs`: the vendored inner command
  execs `apply-seccomp /proc/self/fd/N`, which an empty procfs would break.
  `--args FD` payloads are consumed pre-sweep (fd-path refs + fd-valued option
  values preserved), re-emitted verbatim on fresh post-sweep fds, and argv
  renumbered. Empty/unreadable payloads, missing real bwrap/seccomp artifact,
  and a merged argv lacking an OPTION-POSITION `--unshare-pid`/`--unshare-all`
  all refuse with exit 65.
- **#9725:** `workspaceTenantDenyRoots()` returns the RAW `WORKSPACES_ROOT` +
  `WORKTREE_ROOT` unconditionally (never the flag-collapsed form — the pre-flip
  staging and post-rollback windows stay masked), throws on `"/"`/non-absolute/
  `..`-carrying roots, and adds realpath-canonical aliases via a
  longest-existing-prefix climb (absent leaves and dangling links resolve to
  their canonical target; stat errors other than ENOENT/ENOTDIR throw).
- **#9558:** installation resolve, mint, askpass, clone/reprovision (BOTH warm
  and cold arms — the first fix only gated the warm arm), `resolveC4Eligible`,
  and the stored `GITHUB_TOKEN` Connected-Services key are all gated on
  `runRepoLifecycle`/`sandboxWrite !== "none"`. Egress posture log carries
  `persona` for attribution.

## Key Insight

**`bwrap --args FD` payloads are NOT self-contained argv segments.** Upstream
`bubblewrap.c`'s `--args` arm calls `parse_args_recurse` on the payload and then
does `argv += 1; argc -= 1` — the OUTER parser resumes option parsing after the
payload ends. Consequences that only surfaced in review:

- An inner `--` inside a payload ends only that payload's option stream; outer
  options following the `--args` token still parse as setup options. Any mask
  spliced INSIDE a payload can be mounted over by trailing outer tokens — the
  only correct splice site is the outer setup end.
- The vendored `apply-seccomp` helper execs through `/proc/self/fd/N`, so a
  bare `--tmpfs /proc` mask breaks the spawn; the mask must be a procfs mount.
- A pidns-scoped `--proc` without `--unshare-pid`/`--unshare-all` mounts a
  procfs keyed to the HOST pid namespace — decorative. The check must match the
  flag in OPTION position only: `--setenv K --unshare-pid` puts the same bytes
  in a value slot and must not satisfy it (arity-aware detection, not a flat
  token scan).
- `mapfile` reports SUCCESS on write-only/EOF `--args` fds with an empty array
  — an unchecked re-emit silently drops the whole setup argv (effectively
  unsandboxed spawn). Fail closed on empty.

## Session Errors

1. **Review-pass `else`-arm miss.** The first support-persona gate wrapped only
   the warm `hasActiveQuery` arm; the cold `else` still fired
   `reprovisionWorkspaceOnDispatch`. **Prevention:** when gating a conditional,
   enumerate EVERY path that reaches the gated action — the `if` arm is not the
   gate; the whole `if/else` expression is.
2. **Vacuous mutant row.** `case_write_deny_absent_true_refused` was defined
   after the mutant row that invoked it — bash resolves functions at call time,
   so "command not found" read as the expected RED and the row passed with zero
   coverage. **Prevention:** keep mutant-row case functions in the cases block
   before the matrix, and treat any `command not found` on stderr as a failure.
3. **Regex batch-edit missed multi-line argvs.** A `spawnSync(SHIM, […])`
   single-line regex left multi-line call sites unpatched, producing 14
   cascading failures. **Prevention:** after a mechanical rewrite, run the
   target suite immediately and grep for the OLD shape separately from the new.
4. **Derived-formula test still left the impl constant unpinned.**
   `fdLimit = 3 + countFdValuedOptions(…)` re-derived the formula test-side;
   a `3 → 4` mutation in the impl stayed green. **Prevention:** export the
   baseline constant (`FD_CENSUS_BASELINE`) and pin the constant, not the
   formula.
5. **Inconclusive empirical probes from malformed invocations.** Early direct
   bwrap experiments used payload shapes upstream rejects outright, producing
   noise; the correct claim was settled by reading `bubblewrap.c`'s
   `parse_args_recurse` resume semantics + a valid experiment. **Prevention:**
   when probing a C tool's parser semantics, read the upstream source first —
   malformed-shape results are evidence about the error path, not the feature.

## Post-Merge Addendum — the exposure gate (v0.330.10 rollback → #9803)

The original shim spliced `--proc /proc` into EVERY pidns-carrying argv. On the
merge's first deploy, `ci-deploy.sh`'s blocking probe —
`bwrap --new-session --dev /dev --unshare-pid --bind / / -- true` — routes
through the same PATH shim; it has `--unshare-pid` but NO `--unshare-user`, and
on the in-image bubblewrap 0.8.0 a fresh procfs mount needs a user namespace:
`Can't mount proc on /newroot/proc: Operation not permitted` →
`canary_sandbox_failed` → deploy rollback. Production stayed on the prior
build; the fix shipped as a hotfix release.

**Design correction (#9803):** the mask engages only when the merged setup
stream actually mounts procfs at /proc — bind-family or `--proc`/`--bind-fd`/
`--ro-bind-fd` with dest ≡ /proc (canonicalized: `//proc`, `/proc//`,
`/proc/.`, `/x/../proc` normalize away evasion spellings). A procfs-free argv
passes through untouched; a proc-exposing argv missing option-position pidns
OR userns refuses 65 rather than dying inside mount(2) or shipping the leak.

Session errors / prevention:

6. **Dev-host ≠ shipped-image toolchain masked the failure.** Local and CI
   verification ran on bwrap 0.12.0 where the unconditional splice worked;
   the deploy image carries Debian's 0.8.0, which fails differently (no
   `--args` support at all on 0.8.0 — the multi-payload code path is
   upstream-fidelity hardening only). **Prevention:** when a shim/gate wraps
   a system binary, verify against the version the IMAGE ships, not the dev
   host's — `docker run` the deploy base image and replay the real argv.
7. **A "harmless" defensive splice is not harmless to non-target callers.**
   The probe never mounts procfs — the mask was pure liability there and it
   broke a pinned-by-contract probe argv (#8016 Guard 2) that could not be
   changed. **Prevention:** gate a mutation on the defect shape it exists to
   defeat — "only act when the thing being defended is present" — rather
   than mutating every argv that shares a flag.
8. **Review found the residual holes the same day.** Post-shim review seats
   caught `--bind-fd`/`--ro-bind-fd` dest=/proc (same exposure class, fd2
   arity) and the payload-consume loop's early `break` contradicting the
   resume model. Both are fixed and pinned by discriminating rows.

## Tags

bwrap, procfs, sandbox, cross-tenant, argv-rewrite, fd-hygiene, support-persona, deploy-canary, bwrap-version-drift
