---
title: 'docker masked /proc kills fresh procfs mounts — the #9723 fix must DROP the exposure, not cover it'
date: 2026-10-11
category: engineering
tags: [bwrap, sandbox, procfs, masked-proc, argv-rewrite, security-boundary, cross-tenant]
symptoms: [Every sandboxed agent spawn fails closed, bwrap: Can't mount proc on /newroot/proc: Operation not permitted, faithful canary sandbox_broken since 2026-10-09]
module: WebPlatform
component: agent-sandbox
problem_type: security_issue
resolution_type: code_fix
root_cause: kernel_posture
severity: critical
---

# docker's masked /proc: drop the procfs mount, never cover it — and why four arity walks share one table is a defect class

## Problem

Issue #10032 / incident #9860: after the #9723 fix spliced `--proc /proc` into the
vendored SDK's bwrap argv, **every** sandboxed spawn failed closed in prod.
Docker's default `--masked-paths` includes `/proc`; mounting a fresh procfs inside
a userns over a masked parent procfs EPERMs (`mount_too_revealing` — the kernel
sees hidden inodes below). bwrap 0.8.0 reported
`Can't mount proc on /newroot/proc: Operation not permitted`. The faithful canary
recorded `sandbox_broken` from the first deploy that carried the splice (fail
CLOSED — no unmasked execution ever ran; verified as a non-Art.4(12) event by the
CLO review seat).

## Root cause

Two layers, both load-bearing:

1. **The re-mask was order-dependent AND coverable.** The splice relied on
   later-mounts-wins to cover the vendored tail `--bind /proc /proc` — the same
   mechanism the tail bind used to defeat the denyRead `--tmpfs /proc` in the
   first place (#9723). A covered bind remains a **live host-procfs mount object**
   beneath the cover; any inner process with CAP_SYS_ADMIN in its mount namespace
   (the vendored `apply-seccomp` multicall class, on a permissive posture) can
   `umount(2)` the cover and re-expose it. Later-mounts-wins was the defect's own
   mechanism — a deny that wins the same race inherits the race's fragility.
2. **Prod is not dev, at the syscall level.** Dev bwrap 0.12.0 mounted the fresh
   procfs fine; prod's image pins 0.8.0 under docker's masked `/proc` — a posture
   difference invisible to every host-side test. `--bind-data` EBADFs at write on
   0.8.0 and `--bind-fd` parses but cannot resolve its fd source — two rungs of
   the planned re-home ladder were dead *only on the production binary*.

## Solution

The shim (`apps/web-platform/infra/bwrap-shim/bwrap`, PR #10039) now realizes the
deny by **removal**, not covering:

- **NEUTRALIZE** — `filter_proc_exposure` drops every procfs mount at `/proc`
  (bind-family, `--proc` regardless of dest, `--bind-fd`/`--ro-bind-fd` at
  normalized `/proc`, and bind-family mounts whose **source** normalizes
  at-or-under `/proc` — `--bind /proc /x` mounts host procfs at `/x`) from the
  merged stream: outer argv AND every `--args` payload (selective re-emit; an
  empty-filtered payload writes 0 bytes, not a phantom NUL token). The vendored
  `denyRead` `--tmpfs /proc` lands as the realized mask — an empty tmpfs,
  strictly narrower than the prior pidns-scoped procfs. No procfs mount object
  exists to uncover.
- **RE-HOME** — each unique command-side `/proc/self/fd/N` ref (the vendored
  multicall exec path) gets `--ro-bind <readlink-resolved> /proc/self/fd/N`.
  The single viable rung on 0.8.0. Refuse (exit 65) on deleted/pipe/socket/
  anon/procfs/sysfs-resident/unreadable sources; **skip** (don't refuse) refs
  naming non-open fds — a command merely *mentioning* the path ENOENTs inside,
  and refusing every mention is a spawn-DoS.
- **Refuse closed** on: exposure detected but nothing dropped (walk-desync
  tripwire), nested `--args` in a payload (unfiltered recursion), exposure
  without `--unshare-pid`/`--unshare-user`, unreadable/empty payload.
- **Canary `proc_mask` re-spec**: `[ -d /proc ] || exit 1; for d in /proc/[0-9]*`
  — any real procfs (host bind, fresh procfs, leaked root bind) is
  `proc_mask_defeated`; the empty tmpfs + `self/fd` re-homes pass. Live-drive
  mutation arms pin both defeat shapes.

## What the review panel caught (the durable lesson)

**Four arity walks sharing one table are one defect class.** The shim walks the
merged setup argv four times (outer marks, `setup_marks` per payload,
`rescan_outer`, `filter_proc_exposure`) over a shared `opt_kind` arity table —
but each walk re-implements index advancement. The new filter's `a3` arm strided
3 where every sibling strides 4 (`--overlay` = opt + 3 values): the third value
re-scanned as an operand, the filter broke early, and **a downstream
`--bind /proc /proc` passed through unfiltered while `expose=1` gates passed** —
the exact fail-open this PR exists to kill. Three seats found it independently.
Fixes: `+4` stride + the divergence guard `expose=1 && dropped=0 → refuse`
(detection and drop must agree by construction; a disagreeing pair is a filter
defect, not an input). **Any N-walks-one-table structure needs the check, not
the comment.**

Pre-existing bugs the new call sites amplified: `norm_dest`'s `///`-loop was a
no-op replacement (`${d//\//\/}` = replace `/` with `/`) that hung forever on
`///`-dests — deleted; the segment split already normalizes `//`. The `preserve`
fd-strip needed loop-until-stable (adjacent duplicates survive one global
replace) and a numeric guard (a glob-metachar fd token injects a pattern into
`${var//pat/}`).

## Prevention

- **Verify on the production binary + posture, not the dev binary.** The
  measurement spike (`specs/.../measurements.md`) ran the real image digest —
  bwrap 0.8.0 + docker masked `/proc` — and killed two planned rungs before they
  shipped. Dev/prod divergence in this file has now caused three incidents
  (#9768, #9803, #9860).
- **Dest checks are not enough — check sources too.** A bind with a
  procfs-resident source mounts procfs at an arbitrary dest; a bind-fd whose fd
  survives the drop is an `openat` dirfd channel. Neutralization must strip the
  dropped option's fd from `preserve`, not just the mount tokens.
- **A refusal surface needs per-class diagnostics.** ~10 refuse classes shared
  `bwrap_shim_refused`; the verdict now carries `detail` (first `bwrap-shim:`
  line) folded into deploy-state + Sentry — the no-SSH triage requirement.
- **Substring scans over command text are mention-oracles.** `/proc/self/fd/N`
  inside a `-c` string must scan inside strings, but non-open-fd matches are
  mentions, not refs — skip them, refuse only genuinely unresolvable *open* fds.
- **Anti-vacuity on existence probes**: `for d in /proc/[0-9]*` passes
  vacuously when `/proc` is absent — the `[ -d /proc ]` guard is load-bearing.
- **`for ... done &&` is a status trap**: a loop's exit status is its last body
  command — `done &&` never runs when the body's last test fails. Use `;`.
- **Fast-path predicates must be coverage-equal, not common-case-equal**:
  `proc_dest` first shipped matching only `/proc|*//*|*/|*/.*` — `proc`, `./proc`,
  `../proc` all normalize to `/proc` and evaded detection. Rule: normalize
  anything non-absolute or mutable-spelled, never enumerate the fast cases.

## Session Errors

1. **In-image harness mounted the shim but not the fixture-subst script** —
   `/tmp/fx-subst.sh` missing inside the container → empty `ARGS` →
   `bwrap: execvp /bin/sh`. **Prevention:** verify every harness input is inside
   the container's mount set before diagnosing the DUT.
2. **`preserve` strip's global replace missed the last token** — preserve has no
   trailing delimiter, so `// X /` never matches a terminal ` X`. **Prevention:**
   wrap `" ${x} "` before pattern-substituting space-separated lists; test the
   last element.
3. **`mask`→`have_mask` rename missed the init site and one use** →
   `mask: unbound variable`, 37 test failures. **Prevention:** after any rename,
   grep the old identifier with `git grep -n '<old>'` before committing — the
   residual-zero check belongs on the identifier, not the phrase.
4. **A sed restructure dropped the `proc_dest` guard** — the fd2 drop went
   unconditional for one edit cycle. **Prevention:** surgical replaces that move
   `continue`/`fail` boundaries are read-back reviewed against the diff, not
   `bash -n` alone (syntax-valid control-flow breaks).
5. **`proc_dest` fast-path narrowed detection** (see Prevention above).
   **Prevention:** write the normalization-complete list (non-absolute ||
   mutable), not the common-case list.
6. **`for ... done &&` probe bug** (status trap above). **Prevention:** `;`
   after `done` whenever the tail must run unconditionally.
7. **`printf "--bind..."`** consumed `--bind` as a printf option.
   **Prevention:** `printf --` before any format string that can start with `-`.
8. **Stale inherited claims**: `proc-mask-runtime.test.ts` header still said
   "pidns-scoped outcome"; `session-state.md` cited the abandoned rung ladder;
   `measurements.md` was future-dated (2026-10-13 vs commit date). **Prevention:**
   the CLO/panel record sweep catches it — and the write-time check is "does
   this sentence survive the diff I'm landing?"
9. **`nested --args` first refused via token scan** — over-broad (a `--args`
   *value* would refuse). **Prevention:** positional checks belong inside the
   arity walk, not token greps.

## Related

- `security-issues/bwrap-args-payload-outer-resume-proc-mask-20261009.md` — the
  outer-resume semantics this rewrite's emit position depends on.
- ADR-075 addendum 2026-10-11 (the mechanism-change record); #9723 (the
  isolation guarantee), #9860 (the incident), #9773 (per-tenant executor
  end-state), #10045 (kdeny least-privilege, deferred).

## Correction — 2026-10-12 (#10065)

> The sentences above that call a covered bind "a live host-procfs mount object beneath the cover" and say "No procfs mount
> object exists to uncover" are too strong. The vendored argv begins with a recursive `--ro-bind / /`, so the container's
> own procfs sits beneath the `--tmpfs /proc` after a drop as well; the shim's property is "no argv-requested procfs mount at
> `/proc`", not a kernel-level absence. Every `umount2("/proc")` measured inside the sandbox was EPERM in every arm; the
> attribution to `--cap-drop ALL` on an unelevated bwrap is inferred, not measured. See the ADR-075 addendum dated
> 2026-10-12 (#10065) and `knowledge-base/project/specs/feat-one-shot-10065-sandbox-proc-suite-parity/measurements.md` (M3).
