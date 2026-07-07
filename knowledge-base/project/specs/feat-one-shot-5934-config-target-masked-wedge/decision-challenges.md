# Decision Challenges — feat-one-shot-5934-config-target-masked-wedge

Headless-path record (no interactive operator gate). `/ship` should render these into the
PR body and file an `action-required` issue so the operator sees the challenge.

## UC-1 — Stale premise: the config-target-masked wedge was already fixed elsewhere

**Operator's stated direction:** Implement a `.git/config`-TARGET-masked fix
(`SOLEUR_GIT_CONFIG_TARGET_MASKED` pre-check before the `mv` at `worktree-manager.sh:419`,
graceful `ensure_bare_config` degrade, and "fix why the round-5 guard doesn't fire") as the
resolution to a wedge that "STILL reproduces after round-5."

**Evidence that challenges it (Phase-1, Better Stack, cited per `hr-observability-layer-citation`):**
1. The masked node is `.git/config.lock` (`type=chardevice rdev=1:3`), **not** `.git/config`
   (the target). No telemetry shows the target masked.
2. **Zero** `worktree wedge: could not apply shared-config prerequisites` events over 30d —
   the `ensure_bare_config`/line-492 path is the wrong layer (Sharp-Edge "zero events =
   wrong layer").
3. The real wedge was `ensure_worktree_identity`'s raw `git config --local` EEXIST
   (plain-git RC=255, no marker), **already fixed by #6183** (`696aa4649`, merged
   2026-07-07 14:59 UTC, on `main`).
4. **Zero** `SOLEUR_GIT_LOCK_IDENTITY_WEDGED` events in the 7 days since #6183 — the fix is
   holding. The char-device `config.lock` still appears but is now benign.
5. The "round-5 guard doesn't fire" premise is false — the non-bare guard at
   `worktree-manager.sh:478` returns 0 correctly before any `ensure_bare_config` write on
   the non-bare Concierge clone.

**Resolution taken (evidence-first, per the task's own "do not blind-patch" mandate):**
- Did **not** re-patch the falsified `ensure_bare_config`/identity paths.
- Delivered the genuinely-additive subset: a defense-in-depth `SOLEUR_GIT_CONFIG_TARGET_MASKED`
  self-diagnosis sentinel (guards the unobserved config-target-masked path so a future blind
  session self-diagnoses) + a local mask-simulation test + #5934 scope reconciliation.
- Left #5934 **open** (durable substrate fix + a real telemetry gap: zero
  `SOLEUR_CHARDEV_SWEEP_*` markers in 14d while the char-device keeps appearing → the host
  sweep is not observably running / cannot prevent a per-session bwrap mask).

**Operator action requested:** confirm whether the "still wedges" report predates #6183's
14:59-UTC merge. If it postdates a confirmed live deploy of #6183, re-run the Concierge
canary (#4826) and capture the fresh in-sandbox signature — a NEW post-#6183 signature would
reopen diagnosis on a different path than this plan addresses.
