---
title: "A forbiddance drift-guard written during a refactor tends to guard the OLD mechanism, not the new one"
date: 2026-07-18
category: test-failures
tags: [drift-guard, test-design, refactor, security, review]
issue: 6649
pr: 6686
---

# A forbiddance drift-guard written during a refactor tends to guard the OLD mechanism, not the new one

## Problem

#6649 removed `sudo` from the workspaces-luks host-execution path (the CF-tunnel SSH bridge
lands `-l root`, so `sudo` was redundant AND its `env_reset` scrubbed `HOME`/the sourced `.env`).
Alongside the refactor I wrote two negative drift guards to protect the "boot token never enters
the host process list" invariant:

- H14: `grep -Eq 'sudo[[:space:]]+([A-Za-z_]+[[:space:]]+)*(DOPPLER_TOKEN|…)='` → forbid a
  `sudo VAR=val` argv leak.
- H20: `grep -q 'sudo /usr/local/bin/luks-monitor'` → forbid the old pre-installed-binary call.

Both passed, were mutation-tested, and read as solid. A test-design review agent (prompted with
"find the vacuity the battery MISSED — do not re-run its mutations") found both guard the
**pre-refactor** threat shape: the refactor itself removed `sudo`, so the realistic *next*
regression is the SAME leak via the NEW mechanism — a **sudo-less** `DOPPLER_TOKEN=$x bash …`
argv assignment, or a bare `/usr/local/bin/luks-monitor` call. Both evade a `sudo`-anchored
regex entirely (confirmed against sandbox copies: the predicates returned "holds" while leaking).

## Root cause

When you author a forbiddance guard *during* a refactor that removes mechanism M, the bad-form
you have front-of-mind is "M plus the leak" (`sudo VAR=val`) — because that is what you just
deleted. But M is gone; the code can no longer take that path. The guard therefore protects a
shape the code can no longer produce, while the shape it CAN now produce (the leak without M)
sails through green. A forbiddance predicate that enumerates a specific bad form is only as good
as the author's imagination of bad forms, and a just-completed refactor actively biases that
imagination toward the retired one.

## Solution

**Assert the GOOD form exclusively, mechanism-independently — don't blacklist the specific old bad form.**

- H14 became: the only permitted `(DOPPLER_TOKEN|WORKSPACES_LUKS_BOOT_TOKEN)=` occurrence is the
  printf placeholder `=%s` (the stdin `.env` payload); any `=` NOT immediately followed by `%` is a
  leak — `grep -Eq '(DOPPLER_TOKEN|WORKSPACES_LUKS_BOOT_TOKEN)=([^%]|$)'` — with or without `sudo`,
  `-E`, `--preserve-env`, or an intervening `FOO=bar`.
- H20 became: forbid the `/usr/local/bin/luks-monitor` path regardless of `sudo`.
- Added mutations for the sudo-LESS forms so the guard's own battery proves it catches them.

## Key insight

The litmus (from the review skill's own catalogue): *can you name an implementation a reasonable
engineer might write NEXT that satisfies the assertion while violating the property?* During a
refactor, the highest-probability "next implementation" is the one that reaches the same bad end
via the mechanism you just introduced — so a forbiddance guard anchored on the mechanism you just
removed is vacuous by construction. Prefer whitelisting the good form (verb/prefix/mechanism-blind)
over blacklisting a bad form. This is the refactor-time corollary of "assert the property, not the
shape the code happens to have."

## Session Errors

- **Forbiddance guards H14/H20 encoded the pre-refactor `sudo` threat model** — Recovery: rewrote
  to assert the good form exclusively (sudo-independent) + added sudo-less mutations. **Prevention:**
  this learning; when writing a negative guard during a mechanism-removing refactor, whitelist the
  good form rather than blacklist the removed mechanism.
- **H17 predicate SIGPIPE-flaked** (`strip_comments | grep -q` under `pipefail`, early match →
  SIGPIPE → false 0) — Recovery: herestring form. **Prevention:** already documented in
  [[2026-07-18-pipefail-grep-q-early-match-sigpipe-flakes-drift-guards]]; reused that fix.
- **Over-deferred automatable operator/terraform steps** at the investigate-then-plan boundary —
  Recovery: user corrected; ran the apply-trigger + rehearsal + issue-close autonomously.
  **Prevention:** already enforced by `hr-never-label-any-step-as-manual-without` +
  `hr-exhaust-all-automated-options-before`; an "investigate and return a scoped plan" framing does
  NOT license enumerating automatable steps as terminal operator actions.
