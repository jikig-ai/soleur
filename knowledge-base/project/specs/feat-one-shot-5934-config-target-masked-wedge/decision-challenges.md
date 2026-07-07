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

## UC-2 — Scope refined mid-implementation from live operator diagnostics

**During implementation the operator supplied two decisive data points about the affected
workspace, which re-prioritised the deliverables:**

1. **The workspace is CONFIRMED NON-BARE** (`git rev-parse --is-bare-repository` = false,
   `.git` is a real directory) — yet `ensure_bare_config` still reached its config write and
   wedged. This proves the **round-5 non-bare guard MISFIRED under the mask**: `git rev-parse
   --show-toplevel` returns empty (→ `GIT_ROOT=""`) and `--is-bare-repository` degrades because
   both must read the masked `.git/config`. So the operator-facing fix is **not** "fail loud on
   bare-under-mask" — it is **making the non-bare guard skip the surgery ROBUSTLY**, via a pure
   filesystem probe (`git_dir` is a `.git` directory) that never reads the masked config. Then
   native `git worktree add` (which writes only `.git/worktrees/<id>/`, never `.git/config`)
   proceeds and succeeds **in-sandbox, with no host-side dependency**. This became **D3, the
   primary deliverable**; D2 (target-masked pre-check) is retained as a secondary safety net for
   the rare genuinely-bare case, and D1 makes both paths finally visible.

2. **`extensions.worktreeConfig` is CONFIRMED UNSET** on the workspace → **D4 (self-heal of a
   stale `extensions.worktreeConfig`) was CUT.** Its write-to-`.git/config` mechanism targets
   the exact masked/blocked path, so it added risk without addressing the real bug. Removed
   cleanly (no code, no test). Tracked as a defensive follow-up only if ever observed.

**Marker forensics upgraded:** each marker now records WHICH branch fired —
`branch=non-bare-skip` (benign `SOLEUR_GIT_CONFIG_MASK_SKIP`, mirrored-not-paged),
`branch=bare-fail` (`SOLEUR_GIT_CONFIG_TARGET_MASKED`, paged), `branch=target-masked-precheck`
(the `atomic_git_config` guard) — so telemetry finally shows the exact path taken.

**Local-simulation caveat (documented in the test):** a REAL masked-target inode needs
`mknod`/`mount --bind` (privileged), unavailable on the unprivileged runner. The portable proxy
is a symlink→`/dev/null` (a char device by dereference, the exact `_config_target_masked`
signature) for D2, and `core.bare=true` + empty `GIT_ROOT` to reproduce the D3 guard-misfire
deterministically. Both give a genuine RED→GREEN (not a vacuous pass); the real-char-device arm
is gated on `mknod` for CI-root.
