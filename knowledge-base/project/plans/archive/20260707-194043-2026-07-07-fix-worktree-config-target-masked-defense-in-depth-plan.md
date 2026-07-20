---
title: "fix: worktree config-target-masked wedge — observability meta-fix + target-masked pre-check + bare-under-mask correctness"
date: 2026-07-07
branch: feat-one-shot-5934-config-target-masked-wedge
type: fix
tracking_issue: 5934
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

# fix: worktree `config`-target-masked wedge — observability meta-fix + target-masked pre-check + bare-under-mask correctness

🐛 **Bug-class:** recurring Concierge worktree-creation wedge (#5934 / #6184 family).
**This wedge is LIVE on current `main`, not a hypothetical.** An operator-confirmed
verbatim error from a sandbox running the DEPLOYED current-main code proves the failure
IS the `config`-target-masked wedge — and proves *why* four prior fixes (merged 07-01 →
07-07) never converged: **the fatal outcome is invisible to telemetry.** This plan
corrects an earlier draft that wrongly treated this path as an unobserved defensive
hypothetical already fixed by #6183 (`696aa4649`). That premise is REFUTED (see below).

---

## GROUND TRUTH — operator-confirmed verbatim error (current `main`, not stale)

```
SOLEUR_GIT_LOCK_UNREMOVABLE file=config.lock type=chardevice ... reason=non-regular-lock
mv: cannot move '.git/config.soleur-tmp.4' to '.git/config': Device or resource busy
[error] worktree wedge: could not apply shared-config prerequisites in .git
```

This is the `config`-target-masked wedge, end to end:

1. `sweep_stale_git_locks` detects `.git/config.lock` is a char device →
   `SOLEUR_GIT_LOCK_UNREMOVABLE` (this line DOES reach telemetry — it is an
   `echo "SOLEUR_GIT_LOCK_UNREMOVABLE …"` on stdout, matched by `MARKER_RE`).
2. `ensure_bare_config` (`worktree-manager.sh:490-491`) calls `atomic_git_config` to write
   `.git/config`. The lockless temp-copy+rename `mv -f -- "$tmp" "$target"` at **:419**
   hits **EBUSY** (`Device or resource busy`) because `.git/config` — the rename **TARGET**
   — is itself a bind-mount / masked node.
3. It fails at **:492** with `worktree wedge: could not apply shared-config prerequisites`.

Reaching :492 means the non-bare guard at **:476-480** did **NOT** return early — so on
this workspace the flow is treated as **BARE** (either genuinely bare, or `GIT_ROOT`
resolves empty under the masked config AND `git rev-parse --is-bare-repository` returns
`"true"`). **The fix must be robust to BOTH bare and non-bare** without inspecting the live
sandbox.

### Why the earlier "already fixed / unobserved" premise was WRONG

The prior draft concluded, from a "zero events in 30d" Better Stack query, that the
line-492 path was the wrong layer and already fixed by #6183's `ensure_worktree_identity`
change. That inference inverted cause and effect: **the path fires every time; the zero-event
count is the symptom of the telemetry blindness, not evidence the path is cold.** The
verbatim `mv: … Device or resource busy` + `[error] worktree wedge:` is the direct refutation.

---

## The meta-bug: why telemetry was blind (verified in-repo)

The fatal `[error] worktree wedge:` line is emitted via `headless_or_stderr`
(`.claude/hooks/lib/session-state.sh:358-374`). In the Concierge headless sandbox the branch
`[[ ! -t 2 ]] && [[ -n "$CLAUDECODE" ]]` (`:365`) appends the line to a per-PID logfile
`$LOG_DIR/${PPID}.log` (`:369`) — **NOT** the Bash-tool stdout/stderr that the PostToolUse
telemetry hook scans. Two independent drops stack:

1. **Wrong sink.** The line lands in a logfile the `git-lock-marker-telemetry` PostToolUse
   hook never sees. (Verified: `session-state.sh:365-369`.)
2. **Wrong shape.** Even if it reached stdout, `headless_or_stderr` prefixes it
   `[error] ` (`session-state.sh:371`, and the logfile form at `:369`). `MARKER_RE`
   (`apps/web-platform/server/git-lock-marker-telemetry.ts:48-49`) anchors
   `^(?:…|worktree wedge:.*)$`, so `[error] worktree wedge:` fails the `^worktree wedge:`
   match. (Verified: `git-lock-marker-telemetry.ts:48-49`; the drift-guard test only
   collects `echo "SOLEUR_GIT_…"` literals — `git-lock-marker-telemetry.test.ts:107-128` —
   so a `headless_or_stderr`-only sentinel is not even checked.)

Double-drop → the fatal outcome is invisible in Better Stack (zero events in 30d) **even
though it fires on every wedged run.** This blindness is why four prior fixes (07-01 →
07-07) never converged: each was authored against a symptom the layer above never surfaced.
Cite `hr-observability-as-plan-quality-gate`, `hr-observability-layer-citation`,
`hr-no-dashboard-eyeball-pull-data-yourself`.

Two adjacent fatal/near-fatal markers share the same blindness class and are fixed in the
same pass:
- **`NO_GIT_REPOSITORY`** (`worktree-manager.sh:87`) — a plain `echo … >&2`, not a
  `SOLEUR_*` marker, unmatched by `MARKER_RE`. A repo-less workspace exits 3 invisibly.
- **`SOLEUR_FEATURE_PUSH_FAILED`** (`worktree-manager.sh:1243`) — reaches stdout but is
  **not** in `MARKER_RE`'s allowlist, so it is dropped at ingest.

---

## Overview

### What the operator asked for (corrected scope)
Make the `config`-target-masked worktree wedge (a) **visible** to monitored telemetry, and
(b) **degrade gracefully** instead of shipping a broken worktree, robust to both bare and
non-bare workspaces — while leaving the durable host-side prevention to the already-open
#6191 / #5934. This plan is organized around FIVE deliverables in strict priority order.

### Deliverables (priority order)

- **D1 — Observability meta-fix (highest priority; it is why we have been blind).** Make
  the config-write / worktree-create FATAL paths reach monitored telemetry:
  - **(a)** Emit the wedge conclusion as a clean `SOLEUR_*` marker on **stdout**
    (via `echo`, not only via `headless_or_stderr`'s logfile) at every fatal give-up in
    `atomic_git_config` and `ensure_bare_config` — so the outcome is scanner-visible
    regardless of the headless logfile sink.
  - **(b)** Add `SOLEUR_GIT_CONFIG_TARGET_MASKED` (new, D2), **`SOLEUR_FEATURE_PUSH_FAILED`**
    (`:1243`), and the top-of-file **`NO_GIT_REPOSITORY`** gate (`:84-89`) to `MARKER_RE`
    (ingest allowlist) and to the drift-guard test. Classify the genuinely-fatal ones in
    `WEDGE_RE` (paged); leave benign informational ones as DIAG.
  - **(c)** Handle the `[error] ` prefix so the **existing** `worktree wedge:` line matches
    `MARKER_RE` even when emitted through `headless_or_stderr`. (Anchor the regex to allow
    an optional `[<level>] ` prefix, OR — preferred — also emit a bare `echo` sentinel at
    the give-up site so the match no longer depends on the prefix. Adjudicate at plan-review;
    default = emit a bare stdout sentinel AND relax the anchor, belt-and-suspenders.)

- **D2 — `config`-target-masked pre-check.** In `atomic_git_config`, **before** the doomed
  `mv -f -- "$tmp" "$target"` at `:419` (and defensively at the top of the function, so the
  native branch is covered too), detect that the rename **TARGET** is a mountpoint /
  char-device using the established `[[ -c ]]` + `stat -c%m` idiom already at
  `worktree-manager.sh:187-193`. On a masked target: emit the visible
  `SOLEUR_GIT_CONFIG_TARGET_MASKED` sentinel and **do NOT attempt the rename** (it would
  EBUSY, exactly as the verbatim error shows). Precedent: the lockless-temp sentinel
  `SOLEUR_GIT_LOCK_TEMP_WEDGED` at `:414`.

- **D3 — Correctness for the bare-under-mask case.** The write in `ensure_bare_config` is
  REQUIRED on a genuinely bare repo (it prevents `core.bare` bleeding into worktrees) and is
  IMPOSSIBLE under the mask. Split the two outcomes:
  - If the repo is effectively **non-bare** / `git worktree add` works natively → the bare
    surgery is **not needed**; SKIP it and proceed (the existing non-bare guard at `:476-480`
    already does this — verify it is reached; the verbatim error shows a case where it was
    NOT, so harden the bare-classification so a masked-config non-bare workspace is not
    misread as bare).
  - If **genuinely bare AND target masked** → do NOT silently produce a broken worktree.
    Emit the loud, VISIBLE `SOLEUR_GIT_CONFIG_TARGET_MASKED` marker **naming the host-seed
    remedy** and fail cleanly (non-zero). The durable heal is host-side (pre-seed the config
    before the bwrap mask) — coordinate with the already-open **#6191** and **#5934**; do
    **NOT** close #5934.

- **D4 — Self-heal stale `extensions.worktreeConfig`.** A pre-fix run may have already set
  `extensions.worktreeConfig=true` in `.git/config` while `.git/config.worktree` is masked
  (an unreadable char device) — which makes git read the masked worktree config and
  `fatal … Permission denied` on every command (the hazard the `:459-461` comment names). If
  that stale key is present, **unset it via `--file`-scoped git** (`git config --file
  "$shared_config" --unset extensions.worktreeConfig` — which does NOT read the masked
  `config.worktree`) **EARLY**, before the readiness gate / before the surgery block, so a
  once-poisoned workspace self-heals on the next run.

- **D5 — Local `mknod` mask-simulation test.** A char-device (and, privilege-permitting,
  read-only bind-mount) simulation over a throwaway `.git/config` that reproduces the
  **EBUSY-on-masked-target** locally and asserts: **current** code wedges (generic
  `atomic rename failed`, no visible sentinel), and **fixed** code degrades gracefully +
  emits the visible `SOLEUR_GIT_CONFIG_TARGET_MASKED` marker without attempting the `mv`.
  This makes the whole fix verifiable on a normal checkout (no sandbox required).
  Follow `cq-write-failing-tests-before`.

### Explicit non-goals
- Do NOT close **#5934** — host-side durable prevention (pre-seed before the bwrap mask)
  remains its scope. Reference #5934 + #6191; use `Ref`, not `Closes`
  (`wg-use-closes-n-in-pr-body-not-title-to`).
- Do NOT modify or close **#4826** (nav-rail canary — off-limits).
- Do NOT revert #6183's `ensure_worktree_identity` change (it fixed a *different*,
  real path); this plan is additive to it.

---

## Research Reconciliation — Premise vs. Ground Truth

| Earlier-draft claim | Ground truth (operator-verbatim + in-repo verify) | Plan response |
|---|---|---|
| "The `config`-target-masked path is an unobserved defensive hypothetical." | Verbatim `mv: cannot move … .git/config: Device or resource busy` + `[error] worktree wedge:` on current main. The path fires every wedged run. | Treat as the LIVE root cause. D2 pre-check + D3 correctness. |
| "Already fixed by #6183; line-492 is the wrong layer (zero events/30d)." | Zero events is the *symptom of telemetry blindness*, not a cold path. #6183 fixed a different (identity) path. | D1 meta-fix makes the path visible; do not rely on the zero-event inference. |
| "Only `.git/config.lock` is masked, never `.git/config`." | The verbatim `mv … .git/config: Device or resource busy` shows `.git/config` (the rename TARGET) is masked/bind-mounted. | D2 checks the TARGET, not just the lock. |
| "Non-bare guard at 478 always returns before the write." | Reaching :492 proves it did NOT return early here → workspace treated as bare (empty `GIT_ROOT` + `--is-bare-repository=true`). | D3 handles BOTH bare and non-bare; harden bare-classification. |
| "`SOLEUR_GIT_LOCK_*` are all mirrored." | `worktree wedge:` goes via `headless_or_stderr` → per-PID logfile, not the scanned stdout; `[error]` prefix also fails `MARKER_RE`. `NO_GIT_REPOSITORY` + `SOLEUR_FEATURE_PUSH_FAILED` are unmatched too. | D1(a)(b)(c) fixes sink + shape + allowlist. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** the exact live outage this plan targets —
a Concierge worktree-creation wedge (`mv … Device or resource busy` → `worktree wedge`),
now with the added risk that a false-positive target-masked detection refuses a legitimate
config write on a normal repo. Both are single-user, workflow-blocking. Mitigations:
D5's regression test pins the observed-`config.lock` case so D2 cannot over-trigger; D3's
fail-loud path names the host-seed remedy so a genuinely-bare masked repo fails with an
actionable, visible marker rather than a silently-broken worktree.

**If this leaks, the user's data/workflow is exposed via:** no new data surface. The new
sentinel emits device/path forensic only (`file=config reason=target-bind-mount`), never
identity values or user data — matching the #6183 sentinel discipline.

**Brand-survival threshold:** single-user incident. Justification: the change edits
`atomic_git_config` / `ensure_bare_config`, on every worktree-creation path; a defect strands
a single Concierge user. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at review.

---

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)
- Re-read `atomic_git_config` and `ensure_bare_config` in
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`; re-derive current line
  numbers for the `mv` (~:419), the give-up at ~:492, the non-bare guard (~:476-480), the
  `NO_GIT_REPOSITORY` gate (~:84-89), and `SOLEUR_FEATURE_PUSH_FAILED` (~:1243). Do not
  assume the numbers are frozen.
- Read `session-state.sh:355-378` to confirm the `headless_or_stderr` sink + `[error] `
  prefix behaviour (the meta-bug mechanism).
- Read `git-lock-marker-telemetry.ts` `MARKER_RE` / `WEDGE_RE` and the drift-guard test in
  `git-lock-marker-telemetry.test.ts:107-128` to see exactly how sentinels are collected.
- Read the harness idiom in `plugins/soleur/test/worktree-manager-atomic-config.test.sh`
  (existing T1–T19) to mirror for D5.
- Confirm #6191 and #5934 are OPEN (`gh issue view`) before referencing them.

### Phase 1 — D1: observability meta-fix (telemetry reaches a monitored sink)
Files: `worktree-manager.sh`, `apps/web-platform/server/git-lock-marker-telemetry.ts`,
`apps/web-platform/test/git-lock-marker-telemetry.test.ts`.
- **(a) stdout sentinel at fatal give-ups.** At the `ensure_bare_config` give-up (~:492) and
  the `atomic_git_config` rename-failure (~:419-423), emit a bare `echo "SOLEUR_… …"` on
  stdout *in addition to* the existing `headless_or_stderr error` line, so the conclusion is
  scanner-visible even under the headless logfile sink.
- **(b) allowlist + drift guard.** Add `SOLEUR_GIT_CONFIG_TARGET_MASKED`,
  `SOLEUR_FEATURE_PUSH_FAILED`, and `NO_GIT_REPOSITORY` to `MARKER_RE`. Classify
  `SOLEUR_GIT_CONFIG_TARGET_MASKED` and `NO_GIT_REPOSITORY` as **wedged** in `WEDGE_RE`
  (blocked session → paged); `SOLEUR_FEATURE_PUSH_FAILED` is a wedge too (push failed →
  local-only branch). Update the drift-guard test so it also collects `echo "NO_GIT_REPOSITORY`
  and `echo "SOLEUR_FEATURE_*` forms (its current pattern only matches `echo "SOLEUR_GIT_`),
  and add explicit coverage for each new sentinel + the `[error] `-prefixed `worktree wedge:`.
- **(c) prefix tolerance.** Relax `MARKER_RE`'s `worktree wedge:` arm to allow an optional
  leading `[<level>] ` prefix (e.g. `(?:\[[a-z]+\]\s)?worktree wedge:.*`), so the existing
  `[error] worktree wedge:` matches; combined with the bare stdout echo from (a) this is
  belt-and-suspenders. Add a test asserting `[error] worktree wedge: …` classifies as wedged.
- Cite `hr-observability-as-plan-quality-gate` / `hr-observability-layer-citation` in the
  PR body.

### Phase 2 — D2: `config`-target-masked pre-check (`atomic_git_config`)
File: `worktree-manager.sh`.
- Add a masked-**target** guard: masked iff `[[ -c "$target" ]]` (char device) **OR**
  `$target`'s realpath is a mountpoint (`[[ -n "$rp" && "$(stat -c%m -- "$rp"
  2>/dev/null)" == "$rp" ]]`, copying the exact idiom at `:187-193` — it correctly handles
  `/dev/null` being BOTH `-c` and a mountpoint).
- Placement: primary check **immediately before** the `mv -f -- "$tmp" "$target"` at ~:419
  (the exact EBUSY site from the verbatim error); plus a defensive top-of-function check
  after symlink resolution (~:383-389) so the native `git config --file` branch (~:377) is
  also covered.
- On masked target: emit `SOLEUR_GIT_CONFIG_TARGET_MASKED file=<base>
  reason=target-bind-mount` on stdout, clean up `$tmp`/`$tmp.lock`, and **do NOT** attempt
  the `mv`. Return non-zero (fail-loud; see D3 caller contract).

### Phase 3 — D3: bare-under-mask correctness (`ensure_bare_config`)
File: `worktree-manager.sh`.
- **Non-bare / native-add-works → SKIP the surgery.** Confirm and, if needed, harden the
  non-bare guard at ~:476-480 so a masked-config non-bare workspace (empty `GIT_ROOT`,
  `--is-bare-repository` ambiguous) is NOT misclassified as bare. The verbatim error reached
  :492, so this classification is currently reachable-as-bare on the failing workspace —
  make "indeterminate under mask" resolve to the safe non-bare skip whenever `git worktree
  add` can proceed natively.
- **Genuinely bare AND target masked → fail LOUD + VISIBLE.** `atomic_git_config` returns
  non-zero (D2). `ensure_bare_config` then emits the visible `SOLEUR_GIT_CONFIG_TARGET_MASKED`
  marker **naming the host-seed remedy** (e.g. `remedy=host-pre-seed-.git/config-before-bwrap-mask
  see=#6191,#5934`) and returns 1 — never shipping a `core.bare`-bleeding worktree.
- Record the fail-loud-vs-soft-skip caller contract in the PR body for plan-review.

### Phase 4 — D4: self-heal stale `extensions.worktreeConfig`
File: `worktree-manager.sh`.
- EARLY (before the readiness/surgery block, above the non-bare guard, alongside the
  existing `sweep_stale_git_locks` call at ~:453): if `git config --file "$shared_config"
  --get extensions.worktreeConfig` returns `true` while `.git/config.worktree` is masked
  (char device / mountpoint), **unset it** via `git config --file "$shared_config" --unset
  extensions.worktreeConfig` (the `--file` form does not read the masked `config.worktree`),
  emitting a visible informational `SOLEUR_*` marker. This unwedges a workspace poisoned by
  a pre-fix run so it self-heals rather than `fatal … Permission denied` on every git call.

### Phase 5 — D5: local `mknod` mask-simulation test (RED→GREEN)
File: `plugins/soleur/test/worktree-manager-atomic-config.test.sh` (extend; T20+).
- **T20 (target masked, RED→GREEN):** `mknod config c 1 3` (or `ln -s /dev/null config` for
  unprivileged CI) over a throwaway `.git/config`; call `atomic_git_config`. Assert
  pre-fix code fails with only the generic `atomic rename failed` line and **no**
  `SOLEUR_GIT_CONFIG_TARGET_MASKED`; post-fix code emits the visible sentinel and the `mv` is
  never attempted. Authored to fail first (`cq-write-failing-tests-before`).
- **T21 (mountpoint target):** bind-mount `/dev/null` over `config` if the runner permits
  `mount --bind`; else privilege-aware skip with a logged reason, keeping the `-c` arm as the
  load-bearing assertion (mirror the harness's existing privilege-aware skips).
- **T22 (regression lock, observed `config.lock` case):** char-device `config.lock` +
  regular `config` → `atomic_git_config` still routes around it (lockless temp+rename
  succeeds, **no** `SOLEUR_GIT_CONFIG_TARGET_MASKED`) — pins the #5912/#6183 routing so D2
  cannot over-trigger.
- **T23 (self-heal):** `extensions.worktreeConfig=true` in `config` + masked
  `config.worktree` → the early self-heal unsets the key (D4) and emits its marker.

### Phase 6 — Verify & ship
- `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` green (T1–T23);
  `shellcheck` clean on new shell; `git-lock-marker-telemetry.test.ts` green incl. new
  sentinels + `[error] ` prefix; `tsc --noEmit` clean.
- `gh issue comment 5934` (scope note; remains OPEN, `Ref` not `Closes`) and
  `gh issue comment 6191` (cross-ref D2/D3 as the in-sandbox sibling of the host-side seed).
- Record the corrected-premise User-Challenge in
  `knowledge-base/project/specs/feat-one-shot-5934-config-target-masked-wedge/decision-challenges.md`
  for `/ship` to render into the PR body + file as an `action-required` issue.

---

## Acceptance Criteria

> **Scope update (operator, 2026-07-07): D4 CUT** (self-heal of stale
> `extensions.worktreeConfig`; refuted — the flag is confirmed UNSET on the affected non-bare
> workspace). Priority reordered: **D3 non-bare guard-repair is THE operator-facing fix**
> (the workspace is non-bare and the round-5 guard misfired under the mask), then D1
> observability, D2 pre-check (secondary defense), D5 test refocused on the guard-misfire.

### Pre-merge (PR)
- [x] **AC1** `grep -c 'SOLEUR_GIT_CONFIG_TARGET_MASKED' worktree-manager.sh` ≥ 1 (new sentinel).
- [x] **AC2** A `_config_target_masked` (`[[ -c ]]` + `stat -c%m` mountpoint) guard exists BOTH
  before the native-vs-lockless decision (covering both write paths) AND immediately before the
  `mv -f -- "$tmp" "$target"` line. (T20 was RED on the pre-guard body — no sentinel.)
- [x] **AC3** D1(b): `MARKER_RE` matches `SOLEUR_GIT_CONFIG_TARGET_MASKED`,
  `SOLEUR_GIT_CONFIG_MASK_SKIP`, `SOLEUR_FEATURE_PUSH_FAILED`, and `NO_GIT_REPOSITORY`; D1(c): it
  matches a `[error] worktree wedge:`-prefixed line. The drift-guard test collects and asserts
  all emitted sentinels (incl. the non-`SOLEUR_GIT_`-prefixed `NO_GIT_REPOSITORY`).
- [x] **AC4** D1(a): a bare `echo` stdout sentinel is emitted at all four `ensure_bare_config`
  give-ups and the `atomic_git_config` masked-target pre-check / rename-failure (not only via
  `headless_or_stderr`).
- [x] **AC5** D3: genuinely-bare + masked-config path emits `SOLEUR_GIT_CONFIG_TARGET_MASKED
  reason=bare-under-mask branch=bare-fail` naming the host-seed remedy and returns non-zero;
  the NON-bare path (the operator's live case) SKIPS the surgery via the `.git`-is-a-directory
  probe (mask-robust; emits benign `MASK_SKIP`). Both branches covered by the caller-contract note.
- [x] **AC6** ~~D4 self-heal~~ — **CUT (out of scope; refuted).** Obsoleted by the D4 cut.
- [x] **AC7** `bash worktree-manager-atomic-config.test.sh` exits 0 with T20–T23 passing
  (68 pass / 0 fail / 2 privilege-skips); T22 asserts the observed `config.lock`-masked case
  still routes around (no false sentinel); T23 is the D3 guard-misfire RED→GREEN.
- [x] **AC8** `shellcheck` clean on new shell; `git-lock-marker-telemetry.test.ts` (21) +
  `tsc --noEmit` green.
- [ ] **AC9** No edit closes `#5934` or touches `#4826`; PR body uses `Ref #5934` / `Ref #6191`. (at ship)
- [x] **AC10** `decision-challenges.md` carries the corrected-premise entry (for `/ship`).

### Post-merge (automated)
- [ ] **AC11** `#5934` carries the scope note and remains OPEN; `#6191` carries the
  cross-reference comment (both via `gh issue comment` in `/work` Phase 6 — no operator step).

---

## Observability

```yaml
liveness_signal:
  what: SOLEUR_GIT_CONFIG_TARGET_MASKED (new) + now-visible "worktree wedge:" / NO_GIT_REPOSITORY / SOLEUR_FEATURE_PUSH_FAILED
  cadence: per worktree-creation attempt (event-driven)
  alert_target: Better Stack (soleur-web-platform app_container -> git-lock-marker-telemetry)
  configured_in: apps/web-platform/server/git-lock-marker-telemetry.ts (MARKER_RE ingest allowlist + WEDGE_RE classifier)
error_reporting:
  destination: Better Stack via server-side git-lock-marker-telemetry mirror; stdout sentinel in-sandbox
  fail_loud: yes — distinct stdout sentinel (not only headless_or_stderr's per-PID logfile), non-zero return
failure_modes:
  - mode: config TARGET masked (char-device/mountpoint) — the LIVE wedge (verbatim mv EBUSY)
    detection: SOLEUR_GIT_CONFIG_TARGET_MASKED event in Better Stack (in-surface probe from the sandbox)
    alert_route: WEDGE_RE -> log.error -> Better Stack + Sentry breadcrumb
  - mode: ensure_bare_config give-up ("worktree wedge:")
    detection: now matched even with the [error] prefix + a bare stdout echo (D1 a/c)
    alert_route: WEDGE_RE -> paged
  - mode: repo-less workspace (NO_GIT_REPOSITORY) / push failed (SOLEUR_FEATURE_PUSH_FAILED)
    detection: added to MARKER_RE allowlist (D1b) — previously dropped at ingest
    alert_route: WEDGE_RE -> paged
  - mode: config.lock masked (observed, benign — routes around)
    detection: SOLEUR_GIT_LOCK_DIAG type=chardevice (already wired); D2 must NOT fire here (T22 guards)
    alert_route: informational DIAG (not paged)
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_GIT_CONFIG_TARGET_MASKED --limit 50
  expected_output: >0 rows on a masked-target wedge (self-diagnosing, no SSH); the fix's whole point is that this is no longer zero-when-firing
```

The new sentinel is emitted **from inside the agent bwrap sandbox** and mirrored server-side
by `git-lock-marker-telemetry.ts` — an in-surface probe whose structured fields
(`file`, `reason=target-bind-mount`) discriminate the config-TARGET-masked wedge from the
benign config.lock-masked case in a single event.

---

## Architecture Decision (ADR/C4)

- **Amend ADR-081** (chardevice config.lock substrate sweep): record that the wedge is the
  masked **config TARGET** (not only the lock), that the fatal path was telemetry-blind
  (`headless_or_stderr` sink + `[error]` prefix + `MARKER_RE` gaps), and that the durable
  prevention is host-side pre-seed before the bwrap mask (#6191/#5934). Amendment, no new ordinal.
- **Cite ADR-098** (git-surface topology, #6183) as the canonical bare-vs-non-bare model.
- **C4:** internal shell + telemetry hardening on an already-modeled container (agent sandbox
  / git-worktree surface). No new external actor/system/data store → no C4 element/edge.
  Re-confirm by reading `model.c4` / `views.c4` / `spec.c4` at /work.

---

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** carry-forward (headless plan; CTO lens applied inline).
**Assessment:** plugin-script + telemetry + docs change on the agent-sandbox surface. Core
risks: (1) a false-positive masked-target detection refusing a legitimate write (mitigated by
T22 regression lock + the `-c`/`stat -c%m` precedent idiom); (2) mis-hardening the
bare-classification (mitigated by defaulting "indeterminate under mask" to the safe non-bare
skip). No infra provisioning, no new vendor/secret. The durable bwrap-config change is
deferred to #5934 — a code edit to an existing provisioned surface, not new infrastructure.

### Product/UX Gate
**Tier:** NONE — no user-facing surface; internal tooling/observability change.

---

## Files to Edit
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — D2 target-masked
  pre-check + D3 bare-under-mask correctness + D4 self-heal + D1(a) stdout sentinels.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — D1(b) add
  `SOLEUR_GIT_CONFIG_TARGET_MASKED`, `SOLEUR_FEATURE_PUSH_FAILED`, `NO_GIT_REPOSITORY` to
  `MARKER_RE` + `WEDGE_RE`; D1(c) tolerate the `[error] ` prefix on `worktree wedge:`.
- `apps/web-platform/test/git-lock-marker-telemetry.test.ts` — cover the new sentinels, the
  prefix case, and the broadened drift-guard collection pattern.
- `plugins/soleur/test/worktree-manager-atomic-config.test.sh` — D5 tests T20–T23.
- `knowledge-base/engineering/architecture/decisions/ADR-081-chardevice-config-lock-substrate-sweep.md` — amendment.
- `knowledge-base/project/specs/feat-one-shot-5934-config-target-masked-wedge/decision-challenges.md` — corrected-premise User-Challenge.

## Open Code-Review Overlap
Re-verify at /work with `gh issue list --label code-review` + `jq --arg` (two-stage form).

---

## Test Scenarios
1. **T20** target = char device / symlink→`/dev/null` → pre-fix generic failure; post-fix
   distinct `SOLEUR_GIT_CONFIG_TARGET_MASKED` + no `mv` (reproduces the verbatim EBUSY).
2. **T21** target = bind-mountpoint → same sentinel (privilege-aware skip if no `mount --bind`).
3. **T22** `config.lock` = char device, `config` = regular → routes around (no sentinel) —
   observed-case regression lock.
4. **T23** stale `extensions.worktreeConfig=true` + masked `config.worktree` → self-heal unsets.
5. Telemetry unit tests: new sentinels + `[error] worktree wedge:` classify as WEDGE; drift
   guard collects the non-`SOLEUR_GIT_`-prefixed markers.

## Sharp Edges
- **Do NOT let D2 over-trigger on the observed `config.lock`-masked case** — T22 is the guard;
  the masked node in that case is the LOCK, the target `config` is regular, and the existing
  lockless routing must remain untouched.
- **Bare-classification under a masked config is the subtle part** — default "indeterminate"
  to the safe non-bare skip; only the genuinely-bare-AND-masked case should fail loud.
- The `mknod c 1 3` arm may need root in some CI runners; keep the `ln -s /dev/null` arm as
  the portable load-bearing assertion (mirror the harness's privilege-aware skips).
- **The observability fix is load-bearing, not cosmetic** — without D1 the next wedge is
  invisible again and a 5th blind fix follows. D1 ships in the same PR, not deferred.
