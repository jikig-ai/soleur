# Decision Challenges — feat-one-shot-5934-config-target-masked-wedge

Headless-path record (no interactive operator gate). `/ship` should render these into the
PR body and file an `action-required` issue so the operator sees the challenge.

## UC-1 — Corrected premise: an earlier draft wrongly declared this wedge already-fixed

**Earlier draft's stated conclusion:** The `config`-TARGET-masked path was an unobserved
defensive hypothetical, already resolved by #6183 (`696aa4649`,
bot-aware `ensure_worktree_identity`), because a Better Stack query showed "zero
`worktree wedge:` events over 30 days" — so the line-492 path was "the wrong layer."

**Evidence that REFUTES it (operator-confirmed verbatim error from a sandbox running the
DEPLOYED current-main code):**
```
SOLEUR_GIT_LOCK_UNREMOVABLE file=config.lock type=chardevice ... reason=non-regular-lock
mv: cannot move '.git/config.soleur-tmp.4' to '.git/config': Device or resource busy
[error] worktree wedge: could not apply shared-config prerequisites in .git
```
1. The wedge is LIVE, not hypothetical. The `mv … .git/config: Device or resource busy`
   shows the rename **TARGET** (`.git/config`) is itself masked/bind-mounted — exactly the
   premise the earlier draft dismissed.
2. Reaching `worktree-manager.sh:492` proves the non-bare guard at :476-480 did NOT return
   early → the workspace is treated as bare (or `GIT_ROOT` resolves empty under the mask +
   `--is-bare-repository=true`). The fix must be robust to both bare and non-bare.
3. **The "zero events/30d" was the symptom, not exoneration.** The fatal
   `[error] worktree wedge:` is emitted via `headless_or_stderr`
   (`.claude/hooks/lib/session-state.sh:365-369`), which in the headless sandbox appends to a
   per-PID logfile — NOT the Bash stdout the PostToolUse telemetry hook scans. AND its
   `[error] ` prefix fails `MARKER_RE`'s `^worktree wedge:` anchor
   (`apps/web-platform/server/git-lock-marker-telemetry.ts:48-49`). Double-drop → the fatal
   outcome fired every wedged run yet showed zero events. This blindness is why four prior
   fixes (07-01 → 07-07) never converged.

**Resolution taken (evidence-first):**
- Re-scoped the plan around the LIVE wedge, in priority order:
  1. **Observability meta-fix** — emit the wedge conclusion as a clean `SOLEUR_*` marker on
     stdout (not only the `headless_or_stderr` logfile); add
     `SOLEUR_GIT_CONFIG_TARGET_MASKED`, `SOLEUR_FEATURE_PUSH_FAILED` (:1243), and the
     `NO_GIT_REPOSITORY` gate (:84-89) to `MARKER_RE` + the drift-guard test; tolerate the
     `[error] ` prefix on the existing `worktree wedge:` line.
  2. **Target-masked pre-check** in `atomic_git_config` before the `mv` at :419 (reusing the
     `-c` / `stat -c%m` idiom at :187-193) — do not attempt the doomed rename.
  3. **Bare-under-mask correctness** — non-bare/native-add-works skips the surgery; genuinely
     bare + masked target fails LOUD with a VISIBLE marker naming the host-seed remedy.
  4. **Self-heal** a stale `extensions.worktreeConfig=true` (unset via `--file`-scoped git,
     early) so a once-poisoned workspace recovers.
  5. **Local `mknod` mask-simulation test** proving current code wedges + fixed code degrades
     gracefully with the visible marker.
- Left #5934 **open** — the durable host-side prevention (pre-seed `.git/config` before the
  bwrap mask) remains its scope, coordinated with the open #6191. `Ref`, not `Closes`.

**Operator action requested:** none blocking — the verbatim error already confirms the LIVE
signature. After merge, re-run the Concierge canary (#4826) and confirm the
`SOLEUR_GIT_CONFIG_TARGET_MASKED` event now appears in Better Stack (the fix's whole point is
that the wedge is no longer zero-when-firing).
