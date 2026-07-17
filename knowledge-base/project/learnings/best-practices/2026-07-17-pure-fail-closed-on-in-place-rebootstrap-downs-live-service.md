---
title: A plan-prescribed pure fail-closed check downs a LIVE service when the bootstrap is re-run in place — augment-then-fail-closed
date: 2026-07-17
category: best-practices
tags: [infra, fail-closed, ci-deploy, bootstrap, in-place-reprovision, self-heal, drift-guard]
issues: [6555, 6553]
pr: 6631
---

## Problem

#6555 dropped `--project` from the inngest systemd units and delivered `DOPPLER_PROJECT` via
`EnvironmentFile=/etc/default/inngest-server`. The plan prescribed a **pure fail-closed** guard in
`inngest-bootstrap.sh`: refuse to start any unit if the env-file has no non-empty `DOPPLER_PROJECT=`
line, with a "no in-place re-bootstrap before force-replace" precondition.

That guard is safe on a **fresh** host (cloud-init / the bootstrap heredoc writes the line first).
But it is **fatal on an existing LIVE host**: `ci-deploy.sh` runs `inngest-bootstrap.sh` DIRECTLY on
the co-located web host on every deploy (`ci-deploy.sh` self-documents "the existing-host deploy runs
inngest-bootstrap.sh DIRECTLY on the host"). That host already has a valid `DOPPLER_TOKEN=dp.` in
its env-file, so the bootstrap takes the **preserve branch** and SKIPS the heredoc that would write
`DOPPLER_PROJECT`. A pre-#6555 env-file therefore never gains the line → the pure fail-closed
`exit 1`s → **inngest-server (the founder's users' live cron scheduler) is down until a manual
force-replace.** An immediate single-user incident, produced by the fix's own safety check.

## Root cause

The plan modeled the fail-closed as protecting a *fresh-provision* invariant, but the same guard
runs on an *in-place re-bootstrap* path whose write-the-value branch is skipped (the preserve
branch exists precisely because the token must survive re-bootstraps). A guard that assumes "the
value was just written above" fires in exactly the state where the write was skipped.

## Solution

**Augment-then-fail-closed:** self-heal the common case, and let the fail-closed catch only a
genuinely broken state. In the preserve branch, idempotently append the missing line BEFORE the
backstop runs:

```bash
if ! grep -qE '^DOPPLER_PROJECT=' /etc/default/inngest-server; then
  printf 'DOPPLER_PROJECT=%s\n' "$DOPPLER_PROJECT" >> /etc/default/inngest-server
fi
# ... later, the fail-closed backstop:
grep -qE '^DOPPLER_PROJECT=[^[:space:]]' /etc/default/inngest-server || { log ERROR; exit 1; }
```

Coverage across all host states: fresh dedicated (cloud-init literal) / fresh web (heredoc) /
existing web pre-change (**augment**) / existing web post-change (idempotent no-op). The backstop
now only fires on a truly malformed file, never on the expected in-place path.

## Key insight

**Before shipping a fail-closed guard, ask: "on which code paths does this run, and does the
value it checks get written on ALL of them?"** A guard placed after a write is vacuously safe only
if every path that reaches the guard also reaches the write. A "preserve/skip" branch (env-file,
cache, lock, config) that bypasses the write is exactly where a fail-closed becomes a live outage.
Prefer **self-heal-then-assert** over **assert-only** when the missing state is cheaply and
unambiguously reconstructable — the assert then means "genuinely broken," not "first run on an
existing host." (This is the deployment-safety sibling of "a short-circuit guard must sit AFTER the
recovery it gates.")

Corollary (from the same PR's review): a **source-derived drift guard must match the property, not
one syntactic shape of it.** The FSM↔guard lockstep test matched only a bare `start_server` on its
own line; the FSM's own idiom is compound (`if ! start_server`, `start_server || flag_set aborted`,
or the inlined `systemctl_cmd start "$SERVER_UNIT"` helper body), so a future start in a
non-allowlisted state stayed green. Fix: detect the call in ANY shape + the direct-helper form, and
add an `EXPECTED_START_SITES` count-drift latch (a new/removed site forces re-review). Same class as
`cq-assert-anchor-not-bare-token` / "a gate certifies placement not correctness."

## Session Errors

1. **Plan mis-located the #6556 tag-drift guard** — said `vector-pii-scrub.test.sh AC3/AC3b`
   (correct file), but a first grep glitched and briefly read as "absent." **Prevention:** when a
   plan cites a test-guard location, `git grep` the derivation VARIABLE (`EXPECTED_TAGS`), not a
   prose label — the label can be paraphrased.
2. **Stale worktree base (2 commits behind origin/main)** — #6627's AC3 fix (luks-monitor.sh logger
   placement) + ci-deploy.sh/cloud-init-inngest-bootstrap.test.sh changes I depend on landed after
   my base; surfaced only when AC3 derivation showed EXPECTED=14 ≠ ACTUAL=15. **Prevention:**
   `git fetch origin main` + rebase BEFORE editing shared high-collision files (infra tests) — the
   rebase-before-applying gate; and treat a guard that "fails on main" as a stale-base signal, not
   a new bug.
3. **Plan's pure fail-closed would down the live web host** (the learning above). **Prevention:**
   enumerate every code path a new fail-closed runs on; augment-then-assert when the checked value
   has a skip branch.
4. **`doppler secrets delete` literal in a commit-message body tripped `doppler-secrets-delete-redirect.sh`**
   (false-positive on prose); PreToolUse blocked the whole Bash call, so the preceding `git add`
   never ran → had to re-stage on retry. **Prevention:** the hook is working as intended (defense in
   depth on a dangerous CLI); when a commit MESSAGE must describe a `doppler secrets delete`, phrase
   it as "Doppler secret removal" and keep the `git add` in a SEPARATE Bash call from the commit.
5. **Comment-collision on negative `! grep` assertions vs my own comments (×3)** — a failure-log
   ExecStart message containing "doppler"; a cloud-init env_keep assertion matching its own comment;
   an AC3c comment over-claiming. **Prevention:** anchor every negative body-grep on the syntactic
   construct (`^ExecStart=`, `Defaults!… env_keep`, `//@@SENTINEL@@/`), never a bare token the file
   also names in prose (`cq-assert-anchor-not-bare-token`). Handled correctly inline each time.
6. **SOLEUR-DEBT marker had no `;`-delimited trigger on the marker line** → harvest-debt classified
   it `no-trigger` (review-caught). **Prevention:** the marker LINE itself must read
   `# SOLEUR-DEBT: <ceiling>; <trigger>` — harvest-debt splits per-line on the first `;`; detail on
   following comment lines is invisible to it.
7. **Line-number self-citations (`:47`/`:324`/`:2741`)** violated `cq-cite-content-anchor-not-line-number`
   and `:47` was already stale in the same PR. **Prevention:** cite content anchors
   (`the ${DOPPLER_PROJECT:-soleur} export`), never `:NN`, in comments.
8. **FSM↔guard drift guard vacuous for compound `start_server` forms** (review-caught, fixed +
   mutation-proven). **Prevention:** the corollary insight above.
9. **decision-challenges said cloud-init basename units are "on OTHER hosts"** — false;
   `inngest-nftables.service` is on the inngest host itself. **Prevention:** verify host placement
   by reading the cloud-init file the unit is defined in, not by assumption.
