# Learning: a code-level root cause licenses the fix even when the incident's host discriminator is unavailable

## Problem

RCA #6629 asked *which host* answered `/hooks/deploy-status` with
`seccomp_profile_host_present=false` at the incident instant, and *whether web-1 was
replaced*. Both are the #6536-style "deciding datum" for the per-host hypotheses (H0:
probe hit the seccomp-less web-2 standby; H1/H2: web-1 was replaced). But the datum was
genuinely unavailable: the 2026-07-15 item-4 deploy-status payload predates
`cat-deploy-state.sh`'s `host_id` field, Better Stack at 3-day retention ships both hosts'
container logs under one `host="soleur-web-platform"` tag, and the incident window was
buried in webhook/journald noise. The temptation was to *reason* a verdict ("web-2 was
de-pooled at 14:49, so it must have been web-1") — exactly what the #6536 sharp edge
forbids.

## Solution

Separate the two questions the RCA is actually answering:

1. **Which host / was it replaced?** — mark **UNKNOWN** where the discriminator is
   unavailable. Do not reason CONFIRMED/REFUTED from surrounding facts. H0/H1/H4 stayed
   UNKNOWN; only H5 (REFUTED off a pulled code fact — host-side `test -f`) and H3
   (CONFIRMED off cited CI-workflow line facts) got verdicts.
2. **What is the root cause and does it license a fix?** — this was answerable at the
   **code level, independent of which host was probed**: `grep -nci seccomp
   cloud-init.yml` = **0**. The profile had no boot-time delivery; the sole writer was an
   SSH provisioner reaching running hosts only. So *any* fresh host — a web-1 replacement
   OR the web-2 standby — comes up unenforced. The fix (image-bake delivery + boot
   `--security-opt` + fail-closed) is licensed by that code fact whether or not the probe
   hit web-1 or web-2.

The RCA ships honest UNKNOWNs AND a confirmed fix. The #6628 build-gate ("is
`host_present=false` reachable outside an item-4 run?") was likewise answerable
structurally (YES — the web-2 standby + three CI SSH-leg silent-skip paths), not from the
unavailable per-host datum.

## Key Insight

An RCA has two independently-answerable layers: the **incident-specific** layer (which
host, which apply, what time — often gated behind retention/telemetry gaps) and the
**mechanism** layer (what code path makes the symptom reachable — usually greppable at
HEAD). When the incident layer is UNKNOWN, do not stall or reason a false verdict: if the
mechanism layer is CONFIRMED at code level and the fix is identical across every
unresolved incident-layer branch, the fix ships. Mark the incident-layer verdicts UNKNOWN
and say so in the same document.

Two supporting patterns from this fix:

- **Fail-closed for free via an existing boot sentinel.** The plan wanted a `poweroff -f`
  guard in cloud-init, but cloud-init.yml is byte-budgeted (~200 B under `WEB_GZIP_BUDGET`).
  Placing the seccomp/apparmor install+assert *before* the existing
  `/run/soleur-hostscripts.ok` sentinel write (which the terminal `docker run` block
  already gates a poweroff on) achieved fail-closed with **zero added user_data bytes** —
  reuse the existing fail-closed gate instead of adding a parallel one.
- **The reliable no-SSH detector for a fail-closed poweroff is the Sentry fatal event, not
  Better Stack absence.** The per-host uptime monitor was removed (#5933); LB-pool monitors
  stay green for a drained/standby host, and a poweroffed host runs no crons. Observability
  review caught the RCA's initial over-crediting of Better Stack absence.

## Session Errors

1. **BetterStack `--since` rejected an ISO timestamp** (`2026-07-15T18:00:00Z` →
   DateTime64 TYPE_MISMATCH). Recovery: use `'YYYY-MM-DD HH:MM:SS'`. Prevention: read the
   `betterstack-query.sh` header (it documents the format) before first use. One-off.
2. **`npx vitest` on `bun:test` files** → `Cannot find package 'bun:test'`. Recovery: run
   `bun test`. Prevention: already-covered (use `./node_modules/.bin/<tool>`, not npx) +
   check the test file's runner import (`bun:test` vs `vitest`) before choosing a runner.
3. **`ci-deploy.test.sh` truncated under a `timeout 480` wrapper** (no `RESULT:` line; the
   backgrounded `; echo EXIT=$?` reports the echo's exit). Recovery: re-ran as a plain
   background task and grepped for the `RESULT:` line. Prevention: already-covered (work
   SKILL.md documents both the tail-masking and backgrounded-echo-exit traps) — don't wrap
   a known-long infra test in a short `timeout`; run it unwrapped in the background and
   assert its own summary line.
4. A review agent's first Read hit the non-worktree bare path (stale `toBe(28)`); it
   self-recovered per `hr-when-in-a-worktree-never-read-from-bare`. One-off (agent-side).

## Tags
category: integration-issues
module: apps/web-platform/infra
issue: 6629
