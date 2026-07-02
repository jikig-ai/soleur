---
title: Self-validating regression when the runtime capability can't be verified locally; keep the deterministic proof blocking
date: 2026-07-02
category: best-practices
module: apps/web-platform/infra, ci
issue: 5875
tags: [seccomp, bwrap, ci-gate, regression-test, deterministic, self-validating, set-e, worktree]
---

# Self-validating regression when the runtime capability is unverifiable locally

## Problem

PR3 of #5875 (ADR-079) needed a "would-have-caught" regression proving a **pre-#5874
seccomp profile EPERMs the claude-agent-sdk 0.3.x split `unshare()`** while the
committed profile allows it. The faithful reproduction needs a real `bwrap`
unprivileged user namespace — which requires `kernel.apparmor_restrict_unprivileged_userns=0`.
Both my dev host AND generic GitHub `ubuntu-24.04` runners **default that sysctl to 1**,
and I had no passwordless sudo locally, so `bwrap` failed at "setting up uid map:
Permission denied" **before** reaching the seccomp-gated second `unshare()`. I could
not verify the runtime discrimination locally at all.

Forcing an unverifiable runtime proof into the **merge-blocking** path is the exact
failure mode the #4932→#4941 false-rollback lesson warns against (a gate you can't
prove correct can red-gate every PR). But dropping the proof entirely re-opens #5849's
"nothing forced a look" class.

## Solution

Split the regression into a **deterministic blocking** layer and a **self-validating
runtime** layer:

1. **Structural (always-on, BLOCKING):** a pure `jq` proof that the synthesized
   `seccomp-pre-5874.json` fixture is EXACTLY the committed profile minus the two
   `WITHOUT CLONE_NEWUSER` unshare rules (`committed.syscalls | select(not
   WITHOUT-NEWUSER) == pre5874.syscalls`), guarded by a non-vacuity assertion that
   exactly 2 such rules exist in the committed profile. Deterministic, no docker, no
   sysctl — proves the profile-vs-split-unshare relationship at the structure level.
2. **Runtime (opt-in, SELF-VALIDATING):** `docker run` real `bwrap` under both
   profiles, gated behind `SDK_SANDBOX_REGRESSION_DOCKER=1` (fired from
   `infra-validation.yml` on profile changes). It sets the sysctl **only on the
   ephemeral runner**, then classifies:
   - committed **passes** → baseline healthy → assert pre-5874 EPERMs (would-have-caught).
   - committed **fails with a non-EPERM error** (uid-map/userns unavailable) → **SKIP**
     with a loud warning (the runner can't run the proof), NOT a false-fail.
   - committed **EPERMs** → FAIL (the live profile is genuinely broken for this SDK).

   Prove-the-baseline-passes-FIRST is the load-bearing trick: it converts "my argv/
   analysis might be wrong on this runner" from a silent false-negative into an
   explicit skip-or-clear-fail.

   **Two refinements the first CI run forced (session error #7):** (a) the runtime
   probe must exercise ONLY the gated syscall — the seccomp `unshare()` gate fires from
   `--unshare-user --unshare-pid` BEFORE any mount, so the synthesized argv must carry
   NO `--proc`/`--dev` mounts (those EPERM for container-cap reasons unrelated to the
   gate, and a naive classifier misreads that mount-EPERM as "the profile is broken").
   (b) classify on the DIFFERENCE between the two profiles, not an absolute verdict: a
   committed-baseline failure is ALWAYS an env limitation → SKIP; the only hard FAIL is
   "no discrimination" (both profiles allow the gated syscall). An absolute "committed
   EPERM ⇒ profile broken" rule conflates the env-setup failure with the gate signal.

The deterministic layer + the lockfile-parity/bump-detection gate remain the blocking
guards; the runtime layer is the higher-fidelity confirmation where the env supports it.

## Key Insight

When a regression's faithfulness depends on a **runtime capability you cannot
guarantee on the dev host or the CI runner** (kernel sysctl, privileged syscall,
hardware), do not gate merges on it blind. Ship a **deterministic structural proof**
as the blocking guard and make the **runtime proof self-validating**: assert the
healthy-baseline path succeeds first, and SKIP (never false-fail) when the environment
can't execute it. An unverifiable-but-blocking runtime gate is worse than an advisory
one — it fails the "don't put non-determinism in the merge path" test. This is the CI
analogue of ADR-079's rejection of a paid/non-deterministic model-turn merge gate in
favor of deterministic detection + a human ack.

Cross-refs: `2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`;
`2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`.

## Session Errors

1. **Newly-created worktree silently reaped at 0-commits-ahead.** The fresh PR3
   worktree (created via the work-skill worktree-manager with a session lease) vanished
   mid-session — a sibling `cleanup-merged` evidently treated a branch with 0 commits
   ahead of origin/main as "merged/empty" and reaped it despite the lease. No work was
   lost (I'd made only reads + scratchpad tests). **Recovery:** recreated the worktree;
   re-verified my target files were unchanged on the (advanced) origin/main base.
   **Prevention:** commit an early real commit (first RED test) immediately after
   worktree creation so the branch is never 0-ahead; a 0-commit branch is
   indistinguishable from "merged" to reap heuristics. (Possible tooling gap: the lease
   should protect a 0-commit worktree — worth a `cleanup-merged` audit.)

2. **Best-effort observability write aborted a SUCCEEDED deploy under `set -euo
   pipefail`.** `write_seccomp_profile_hash` did `sha=$(sha256sum "$host_path" | cut ...)`;
   with the profile file absent (test env), the failing pipe under `pipefail` made the
   assignment exit non-zero → `set -e` aborted `ci-deploy.sh` with rc 1, failing every
   happy-path deploy test. **Recovery:** `[[ -f "$host_path" ]]` guard + `|| true` inside
   the substitution + `sha=""` default; the helper now truly always returns 0.
   **Prevention:** any best-effort/observability write reached under `set -e` must not
   let a deliberately-nonzero command-substitution abort — guard existence and append
   `|| true`. (Already an AGENTS foot-gun class; this is a fresh instance.)

3. **Baseline diffing was essential to attribute the failure.** The 10-vs-6 failure
   counts (mine vs pristine origin/main) — NOT the raw "10 failed" — is what isolated
   error #2 from the pre-existing flaky cron-drain/doppler failures. **Prevention:**
   when a touched-file suite shows failures, diff against the pristine base in an
   ISOLATED copy dir before concluding regression; never assume all failures are yours.

4. **A fixed-char-window assertion was fragile for a last-in-list token.** The apparmor
   plan/apply co-target test copied the #5873 `yml.slice(idx, idx+800)` window; because
   `apparmor_bwrap_profile` is the LAST `-target=`, the window spilled into the apply
   block (43-char margin from false-passing a dropped plan `-target`). Caught by
   pattern-review; **recovery:** bound precisely on `[planIdx, applyIdx)` and the next
   step marker; mutation-verified. **Prevention:** never bound a "must contain X" grep
   with a fixed char window when X can appear in an adjacent block — bound on the
   structural boundary (next invocation / next step).

5. **A destructive file-swap + slow-test + restore in ONE bash command lost my edits on
   timeout.** `git show origin/main:ci-deploy.sh > ci-deploy.sh; <2min test>; cp back`
   hit the 2-minute tool timeout before the restore ran, leaving the pristine file in
   place. **Recovery:** detected via `grep -c write_seccomp_profile_hash` and restored
   from a saved copy; re-ran the baseline in an isolated copy dir instead.
   **Prevention:** never overwrite a working-tree file you're mid-editing to run a
   slow comparison — copy the whole dir and swap the file THERE.

6. **Pre-existing/env failures (one-off, no action):** 2 `missing doppler CLI` ci-deploy
   test failures (present on pristine origin/main — doppler not mocked on my host) and
   non-deterministic cron-drain T-tests (timing-sensitive under host load).

7. **The docker-bwrap regression false-FAILed on its FIRST real CI run** — the exact
   env-fidelity risk this learning is about. Because I couldn't run bwrap userns
   locally (sysctl=1), the runtime layer was unvalidated until CI. On the runner
   (sysctl=0), the committed profile's `--proc /proc` MOUNT step EPERM'd (container
   caps), and my absolute classifier read that as "committed profile broken" → FAIL.
   The check was non-required (didn't block auto-merge), but shipping it red is wrong.
   **Recovery:** dropped `--proc`/`--dev` from the synthesized argv (the unshare gate
   fires before any mount) and switched to a differential classifier (committed failure
   → SKIP; only "no discrimination" → FAIL). **Prevention:** a runtime probe for a
   specific gated syscall must isolate THAT syscall from env-dependent setup steps, and
   verdict on the profile DIFFERENCE, never an absolute per-profile pass/fail. Corollary:
   an env-unverifiable runtime check belongs on a NON-required lane so its first-run
   surprise cannot block merges — put the deterministic proof on the required lane.
