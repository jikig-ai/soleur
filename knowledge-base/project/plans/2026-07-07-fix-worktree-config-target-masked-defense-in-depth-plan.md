---
title: "fix: worktree config-target-masked self-diagnosis (defense-in-depth) + #5934 scope reconciliation"
date: 2026-07-07
branch: feat-one-shot-5934-config-target-masked-wedge
type: fix
tracking_issue: 5934
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

# fix: worktree `config`-target-masked self-diagnosis (defense-in-depth) + #5934 scope reconciliation

🐛 **Bug-class:** recurring Concierge worktree-creation wedge (#5934 / #6184 family).
**Verdict from Phase-1 telemetry: the supplied premise is STALE.** The user-facing wedge
was already root-caused and fixed by **#6183** (`696aa4649`, bot-aware
`ensure_worktree_identity`, merged 2026-07-07 14:59 UTC, on current `main`). The
`config`-TARGET-masked / `ensure_bare_config` path this task hypothesizes has **zero
telemetry events over 30 days** — it is the wrong layer. This plan therefore does **not**
re-patch the falsified path. It delivers the genuinely-additive, evidence-consistent
subset the task asks for and corrects the record on #5934.

---

## Enhancement Summary

**Deepened on:** 2026-07-07. **Round:** 1 (mandatory gates + citation/precedent verification).

### Key improvements from deepen
1. **Telemetry mirror two-regex catch.** The new sentinel must be added to **both**
   `MARKER_RE` (ingest allowlist, `git-lock-marker-telemetry.ts:48`) and `WEDGE_RE`
   (classifier, `:57`). Adding only to WEDGE_RE is a silent no-op — the line would never
   reach Better Stack. Files-to-Edit + Observability corrected.
2. **Precedent-diff gate (masked-target detection).** The `[[ -c ]]` + `stat -c%m`
   mountpoint idiom my D1 guard reuses already exists verbatim at
   `worktree-manager.sh:187-193` (`sweep_stale_git_locks`): `[[ -n "$rp" &&
   "$(stat -c%m -- "$rp" 2>/dev/null)" == "$rp" ]]`. D1 MUST copy this exact form (it
   correctly handles the `/dev/null`-is-BOTH-`-c`-AND-a-mountpoint case the comment at
   `:192` calls out). **Not a novel pattern** — established precedent, low review risk.
3. **All live citations verified:** `696aa4649` is an ancestor of `main`; #6183 MERGED
   14:59 UTC; #6184/#6191 OPEN; ADR-081 file present; rule IDs
   `hr-observability-layer-citation`, `hr-no-dashboard-eyeball-pull-data-yourself`,
   `wg-use-closes-n-in-pr-body-not-title-to`, `cq-write-failing-tests-before`,
   `hr-weigh-every-decision-against-target-user-impact` all ACTIVE; learning
   `2026-06-30-verify-the-fixed-code-path-actually-executes...` exists.

### Gate results
- Phase 4.6 User-Brand Impact: PASS (threshold `single-user incident`, concrete content).
- Phase 4.7 Observability: PASS (5 fields, `discoverability_test.command` SSH-free).
- Phase 4.8 PAT-shaped: PASS (no PAT-shaped var/literal).
- Phase 4.9 UI-wireframe: skip (no UI-surface file).
- Phase 4.5 network-outage / 4.55 downtime-cutover: skip (no trigger).

### New consideration discovered
- The `_config_lock_wedged` gate (`:311`) keys on `<file>.lock`, so a target-`config`-masked
  case where the `.lock` is absent/regular takes the **native** writer branch (`:375`),
  not the lockless branch — D1's guard must sit at the TOP of `atomic_git_config` (before
  the native-vs-lockless fork), not only just before the `mv`, to catch both branches.
  Reflected in Phase 1 ("post-symlink-resolution ~389 **and** defensively before ~419").

## Overview

### What the operator asked for
Add a `config`-TARGET-masked pre-check + a distinct `SOLEUR_GIT_CONFIG_TARGET_MASKED`
sentinel before the `mv -f` at `worktree-manager.sh:419`; make `ensure_bare_config`
degrade gracefully instead of `return 1`; fix "the primary root cause (why the round-5
guard doesn't fire)"; and pursue a host-side durable pre-seed. The premise: the wedge
"STILL reproduces after round-5" and "the live failure is the `.git/config` TARGET itself
being masked."

### What Phase-1 diagnosis (REAL telemetry) actually found

Pulled directly from Better Stack (ClickHouse HTTP SQL via
`scripts/betterstack-query.sh`, Doppler `soleur/prd_terraform`; source
`soleur-web-platform` app_container → `git-lock-marker-telemetry`), cited per
`hr-observability-layer-citation`, data pulled per `hr-no-dashboard-eyeball`:

1. **The mask is on `.git/config.lock`, NOT on `.git/config` (the target).** Live
   runtime forensic (30-day window, `rdev=`-anchored to exclude PR-body prose noise):
   ```
   SOLEUR_GIT_LOCK_DIAG file=config.lock type=chardevice owner=65534:65534 perms=666 age=312 mount=none rdev=1:3 whiteout=no
   SOLEUR_GIT_LOCK_UNREMOVABLE file=config.lock type=chardevice rdev=1:3 errno=none reason=non-regular-lock
   ```
   `rdev=1:3` is `/dev/null`'s major:minor. The masked node is the **lock**, and it is a
   bare char-device node (`mount=none`), not a bind-mount. **No telemetry anywhere shows
   `.git/config` itself being a char device or mountpoint.** The task's central premise
   ("the `.git/config` TARGET itself being masked") is unsupported by the data.

2. **The `ensure_bare_config` / `mv`-at-419 path is the WRONG LAYER.** Issue **#6184**
   (the correctly-scoped tracker, authored this session from the same telemetry) states
   verbatim: *"`_config_lock_wedged()` ALREADY classifies a chardevice as wedged, so
   `atomic_git_config` would already route around it — but that function is never reached
   on the failing path. Over 30 days there are **zero** `worktree wedge: …` events."*
   `worktree wedge: could not apply shared-config prerequisites` is exactly the string at
   `worktree-manager.sh:492` this task told me to fix. **Zero events on the path = the
   Sharp-Edge "wrong layer" signal** (`2026-06-30-verify-the-fixed-code-path-actually-executes`).

3. **The real failing path was `ensure_worktree_identity`, already fixed by #6183.** The
   wedge was an *identity-authority inversion*: on the non-bare Concierge workspace,
   `--global` is the sandbox image's `github-actions[bot]` and `--local` is the
   host-seeded workspace **owner**; the old code did a raw `git config --local` write that
   `EEXIST`ed (RC=255, **plain-git error, no `SOLEUR_GIT_LOCK_*` marker**) on the masked
   `config.lock`. That is why six telemetry-blind rounds missed it. #6183 made
   `ensure_worktree_identity` bot-aware (reads the owner, **zero writes** when a non-bot
   local is present) and added the `SOLEUR_GIT_LOCK_IDENTITY_{WEDGED,DIAG}` sentinels
   mirrored server-side by `git-lock-marker-telemetry.ts`.

4. **#6183's fix is holding.** **Zero `SOLEUR_GIT_LOCK_IDENTITY_WEDGED` events in the 7
   days since #6183 merged.** The char-device `config.lock` still appears
   (`mtime` ≈ 2026-07-07 15:20 UTC, *after* #6183's 14:59 merge) but is now **benign** —
   the code routes around it.

5. **"Why doesn't the round-5 guard fire?" — it DOES fire, correctly.** Round-5 =
   `ef8912bf2` (empty-`GIT_ROOT` non-bare guard). On the non-bare Concierge clone the
   guard at `worktree-manager.sh:478` (`[[ -d "$GIT_ROOT/.git" || "$_bare_status" != "true" ]]
   && return 0`) returns **0 before any `ensure_bare_config` write is attempted**. There
   is **no round-5-guard bug to fix**; the premise that line 492 is reached post-round-5
   is false. (The task's "round-5 … merged 14:59 UTC" is actually #6183, the *round-6
   identity* fix — a numbering slip in the brief.)

### What this plan delivers (evidence-consistent subset)

- **D1 — `config`-target-masked self-diagnosis (defense-in-depth).** Add a target-is-masked
  pre-check (`test -c`, plus mountpoint via `stat -c%m`) inside `atomic_git_config`,
  emitting a distinct `SOLEUR_GIT_CONFIG_TARGET_MASKED` sentinel, so **if** the mask ever
  migrates from `config.lock` to `config` itself, the next blind session self-diagnoses
  in one event instead of triggering a 7th investigation. This guards a
  **structurally-possible-but-currently-unobserved** path — explicitly labeled as
  defense-in-depth, NOT as the fix for the (already-fixed) observed wedge.
- **D2 — local mask-simulation test.** A `mknod`-based char-device (and read-only
  bind-mount) simulation over a throwaway `.git/config` proving current code `EBUSY`s with
  only the generic "atomic rename failed" line, and the D1 code degrades to the distinct
  sentinel. Required deliverable — without it D1 is unverifiable. Also lock in the
  `config.lock`-masked routing (the observed case) so it can never silently regress.
- **D3 — #5934 scope reconciliation (docs/issue).** Broaden/correct #5934 to reflect
  reality: the user-facing wedge is resolved (#6183/#6184); #5934 remains open as the
  *durable substrate* fix (stop the sandbox materializing the char-device at all) plus a
  telemetry gap (below). Reference, do not close.
- **D4 — surface the durable + host-side gaps as linked follow-ups (not silently dropped):**
  (a) the host-side pre-seed / raw-config-write hardening the task names is **already
  filed as #6191** — annotate, don't duplicate; (b) the **char-device sweep is not
  observably running** (zero `SOLEUR_CHARDEV_SWEEP_*` markers in 14d, while the
  char-device keeps appearing) — the true durable fix is in the bwrap config
  (`agent-runner-sandbox-config.ts`), since a deploy-time host sweep cannot prevent a
  *per-session* bwrap mask. File/annotate on #5934.

### Explicit non-goals (falsified by evidence — do NOT do)
- Re-patching `ensure_bare_config`'s `return 1` at line 492 as a live-wedge fix (zero
  events; already guarded by the non-bare early-return; #6183 fixed the real path).
- Claiming/fixing a "round-5 guard doesn't fire" bug (it fires correctly).
- Modifying or closing #4826 (the nav-rail canary — off-limits).
- Modifying `ensure_worktree_identity` (fixed by #6183; zero post-fix wedge events).

---

## Research Reconciliation — Premise vs. Codebase/Telemetry

| Premise (task brief) | Reality (Phase-1 evidence) | Plan response |
|---|---|---|
| "The live failure is the `.git/config` TARGET being masked." | Telemetry: only `.git/config.lock` is a char device (`rdev=1:3`); no event shows `config` masked. | Reframe as defense-in-depth for an unobserved path (D1), not a live fix. |
| "`could not apply shared-config prerequisites` (line 492) is reached post-round-5." | #6184: **zero** such events over 30d; non-bare guard (478) returns 0 before those writes on the Concierge clone. | Do not patch line 492; document why it is unreachable on non-bare. |
| "Round-5 guard must not be returning early (or the wedge moved)." | The wedge **moved** — to `ensure_worktree_identity`, fixed by #6183. Guard fires correctly. | Phase-1 conclusion = "wedge moved & is fixed"; no guard bug. |
| "Still wedges after round-5." | Round-5 = `ef8912bf2`; the *latest* fix is #6183 (round-6 identity, 14:59 UTC). Zero `IDENTITY_WEDGED` in 7d since. Premise likely predates #6183. | Record as User-Challenge / decision-challenge (headless); proceed evidence-first. |
| "Pre-seed `.git/config` host-side (worktree-config-seed.ts / workspace.ts)." | Already tracked as **#6191** (workspace.ts:236/246 raw-config-write hardening). | Annotate #6191, don't duplicate (D4a). |
| "`SOLEUR_GIT_LOCK_*` mirrored to Better Stack." | True **now** (#6183 added `git-lock-marker-telemetry.ts`); the older followthrough script's "not mirrored" note is outdated. In-sandbox lines ARE queryable via the app_container source. | Telemetry pulled successfully; no blocker. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** a false-positive `config`-target-masked
detection in `atomic_git_config` could refuse a legitimate config write on the
worktree-creation critical path, re-introducing a Concierge wedge — the exact
single-user outage class this family has caused six times.

**If this leaks, the user's data/workflow is exposed via:** no new data surface. The new
sentinel emits device/path forensic only (`file=config reason=target-bind-mount`), never
identity values or user data — matching the #6183 sentinel discipline.

**Brand-survival threshold:** single-user incident. Justification: the change edits
`atomic_git_config`, which is on every worktree-creation path; a defect could strand a
single Concierge user. `requires_cpo_signoff: true`; `user-impact-reviewer` runs at
review. (The change is defensive and the observed wedge is already fixed, but the
critical-path locus warrants the conservative threshold.)

---

## Implementation Phases

### Phase 0 — Preconditions (verify before any edit)
- Confirm current `main` HEAD includes `696aa4649` (bot-aware identity) — `git log`.
- Confirm `atomic_git_config` still has **no** `test -c "$target"` before the `mv -f` at
  line ~419 (grep). Re-derive line numbers; do not assume they are frozen.
- Confirm the test suite path `plugins/soleur/test/worktree-manager-atomic-config.test.sh`
  exists (it does — T1–T19 from #6183 live here) and read the last test's harness idiom
  (tmp `.git` dir setup) to mirror for D2.
- Re-run the two confirming telemetry queries (chardevice DIAG present; `IDENTITY_WEDGED`
  zero) to ensure the diagnosis has not shifted between plan and work.

### Phase 1 — D1: target-masked pre-check + distinct sentinel (`atomic_git_config`)
File: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- **Placement (deepen-corrected):** put the guard at the **top of `atomic_git_config`**,
  after resolving the real target (handling the `-L` symlink case as the existing code does
  at ~384-389), **before** the FR2 read-first block and the native-vs-lockless fork at ~375.
  Rationale: if `config` (target) is masked but its `.lock` is absent/regular,
  `_config_lock_wedged` returns 1 and control takes the **native** `git config` branch
  (~377), never reaching the `mv` at ~419 — so a guard placed only before the `mv` misses
  that path. A top-of-function guard covers both branches. (Keep a cheap defensive re-check
  before the `mv` as belt-and-suspenders.)
  - masked iff `[[ -c "$target" ]]` (char device) **OR** `target` is a mountpoint
    (`[[ -n "$rp" && "$(stat -c%m -- "$rp" 2>/dev/null)" == "$rp" ]]` on the realpath `$rp`,
    copying the exact idiom at `worktree-manager.sh:187-193` — it correctly handles the
    `/dev/null`-is-BOTH-`-c`-AND-a-mountpoint case).
  - On masked target: emit **`SOLEUR_GIT_CONFIG_TARGET_MASKED file=<base> reason=target-bind-mount`**
    (precedent: `SOLEUR_GIT_LOCK_TEMP_WEDGED` at line 414), clean up `$tmp`/`$tmp.lock`,
    and return per the graceful-degrade decision below. **Do not attempt the `mv`.**
- **Graceful-degrade decision (held for plan-review — the task's tradeoff):** distinguish
  the two callers. `atomic_git_config` itself cannot know bare-vs-non-bare, so encode the
  decision at the **caller** contract, not by softening the helper unconditionally:
  - **Preferred (Option A):** `atomic_git_config` returns **non-zero** on a masked target
    (fail-loud, symmetric with every other write-failure return). `ensure_bare_config`
    already returns 0 on non-bare *before* reaching these writes (guard at 478), so a
    non-bare clone never hits this; a genuine bare repo under the mask surfaces loudly
    (correct — the write is genuinely needed and impossible in-sandbox → must be
    host-seeded). This preserves "non-bare = safe skip (upstream), genuine-bare =
    surface-loud" **without** a blanket soft-skip that could mask a real bare-repo
    failure. Recommended.
  - **Option B (rejected unless review overrides):** make `atomic_git_config` return 0
    (soft-skip) on a masked target. Rejected: on a genuine bare repo this silently ships a
    subtly-broken worktree (core.bare bleed) — the exact hazard the task flags.
  - plan-review (DHH / Kieran / code-simplicity + architecture-strategist at the
    single-user threshold) adjudicates A vs B. Default = A.

### Phase 2 — D2: local mask-simulation test (RED→GREEN)
File: `plugins/soleur/test/worktree-manager-atomic-config.test.sh` (extend; T20+)
- **T20 (RED against pre-D1 code):** build a throwaway dir; `mknod config c 1 3` (or, if
  `mknod` needs privilege in CI, `ln -s /dev/null config` — a symlink to a char device
  exercises the same `-c` after realpath); call `atomic_git_config` on it; assert
  pre-D1 code fails with only the generic "atomic rename failed" line and **no**
  `SOLEUR_GIT_CONFIG_TARGET_MASKED`. After D1, assert the distinct sentinel **is** emitted
  and the `mv` is never attempted.
- **T21:** mountpoint-shaped target (bind-mount `/dev/null` over `config` if the CI runner
  permits `mount --bind`; else guard-skip with a logged reason and keep the `-c` arm as
  the load-bearing assertion — mirror the harness's existing privilege-aware skips).
- **T22 (regression lock, observed case):** char-device **`config.lock`** present + a
  regular `config`; assert `atomic_git_config` still routes around it (lockless temp +
  rename succeeds, **no** `SOLEUR_GIT_CONFIG_TARGET_MASKED`) — pins the #6183/#5912 routing
  so D1 cannot over-trigger on the real signature.
- Follow `cq-write-failing-tests-before`: T20 authored to fail on current code first.

### Phase 3 — D3/D4: issue + docs reconciliation (no silent drops)
- **#5934:** post a scope-broadening comment (per task): user-facing wedge resolved by
  #6183/#6184; #5934 now scopes the *durable substrate* fix (stop `agent-runner-sandbox-config.ts`
  from materializing the `/dev/null` char-device at `.git/config.lock`) + the sweep
  telemetry gap (zero `SOLEUR_CHARDEV_SWEEP_*` in 14d while the char-device keeps
  appearing — the followthrough soak `chardevice-wedge-nonrecurrence-5934.sh` is currently
  TRANSIENT/never-PASS). Note the D1 sentinel is defense-in-depth insurance. **Ref, not
  Closes.**
- **#6191:** add a one-line comment that this PR's D1 is the in-sandbox sibling of #6191's
  host-side raw-config-write hardening; keep #6191 as the host-side durable owner.
- **ADR amendment:** amend **ADR-081** (`ADR-081-chardevice-config-lock-substrate-sweep.md`)
  with the Phase-1 finding — a deploy-time host sweep cannot prevent a *per-session* bwrap
  mask, so the char-device recurs benignly; the durable prevention is bwrap-config-side.
  No new ADR ordinal (amendment). Confirm ADR-098 (git-surface topology, #6183) already
  captures the non-bare-guard model — cite, do not duplicate.

### Phase 4 — Verify & ship
- `plugins/soleur/test/worktree-manager-atomic-config.test.sh` (all T1–T22) green;
  `shellcheck` clean on the new code; existing git-worktree suites green.
- Record the stale-premise User-Challenge to
  `knowledge-base/project/specs/feat-one-shot-5934-config-target-masked-wedge/decision-challenges.md`
  for `/ship` to render into the PR body + file as an `action-required` issue (headless
  path — no operator to confirm interactively).

---

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** `grep -c 'SOLEUR_GIT_CONFIG_TARGET_MASKED' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` ≥ 1 (new sentinel present).
- [ ] **AC2** A `[[ -c "$target" ]]` (and `stat -c%m` mountpoint) guard exists **before** the `mv -f -- "$tmp" "$target"` line — verified by reading the function, and by T20 failing on a `git stash`-reverted copy of the pre-guard body.
- [ ] **AC3** `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` exits 0 with T20–T22 present and passing; T22 asserts the observed `config.lock`-masked case still routes around (no false `SOLEUR_GIT_CONFIG_TARGET_MASKED`).
- [ ] **AC4** `shellcheck plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` reports no new findings.
- [ ] **AC5** Graceful-degrade decision (Option A vs B) is recorded in the PR body with the plan-review adjudication; `ensure_bare_config` line-492 path is **not** modified (grep shows the block unchanged).
- [ ] **AC6** No edit touches `ensure_worktree_identity`, `#4826`, or closes `#5934` (`git diff` scoped to `atomic_git_config` + tests + docs/ADR only).
- [ ] **AC7** `decision-challenges.md` exists with the stale-premise entry (for `/ship` to surface).

### Post-merge (operator / automated)
- [ ] **AC8** `#5934` carries the scope-broadening comment and remains **open**; PR body uses `Ref #5934` (not `Closes`) — ops-remediation-class per `wg-use-closes`. Automatable via `gh issue comment` in `/work` Phase 3 (no operator step).
- [ ] **AC9** `#6191` carries the cross-reference comment (via `gh issue comment`).
- [ ] **AC10** ADR-081 amendment merged; `grep -l 'per-session bwrap mask' knowledge-base/engineering/architecture/decisions/ADR-081*.md` returns the file.

---

## Observability

```yaml
liveness_signal:
  what: SOLEUR_GIT_CONFIG_TARGET_MASKED (new) + existing SOLEUR_GIT_LOCK_* in-sandbox lines
  cadence: per worktree-creation attempt (event-driven, not periodic)
  alert_target: Better Stack (soleur-web-platform app_container -> git-lock-marker-telemetry)
  configured_in: apps/web-platform/server/git-lock-marker-telemetry.ts (add sentinel to BOTH MARKER_RE ingest allowlist AND WEDGE_RE classifier)
error_reporting:
  destination: Better Stack via server-side git-lock-marker-telemetry mirror; stdout in-sandbox
  fail_loud: yes — distinct sentinel string, non-zero return (Option A)
failure_modes:
  - mode: config TARGET masked (char-device/mountpoint) — currently unobserved
    detection: SOLEUR_GIT_CONFIG_TARGET_MASKED event in Better Stack (in-surface probe, emitted FROM the sandbox)
    alert_route: git-lock-marker-telemetry WEDGE_RE -> existing Sentry mirror path
  - mode: config.lock masked (observed, now benign)
    detection: SOLEUR_GIT_LOCK_DIAG type=chardevice (already wired); D1 must NOT fire here (T22 guards)
    alert_route: informational DIAG (not paged)
  - mode: durable char-device sweep not running (zero SOLEUR_CHARDEV_SWEEP_DONE in window)
    detection: scripts/followthroughs/chardevice-wedge-nonrecurrence-5934.sh (TRANSIENT today)
    alert_route: scheduled-followthrough-sweeper.yml -> #5934
logs:
  where: Better Stack ClickHouse warehouse (queryable via scripts/betterstack-query.sh)
  retention: per Better Stack source config (host_scripts_journald + app_container)
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_GIT_CONFIG_TARGET_MASKED --limit 50
  expected_output: zero rows in normal operation (unobserved path); >0 iff a real config-target mask ever occurs — self-diagnosing, no SSH
```

Affected-surface note (2.9.2): the new sentinel is emitted **from inside the agent bwrap
sandbox** and mirrored server-side by `git-lock-marker-telemetry.ts` — an in-surface probe
whose structured fields (`file`, `reason=target-bind-mount`) discriminate the
config-target-masked hypothesis from the config.lock-masked one in a single event.

---

## Architecture Decision (ADR/C4)

### ADR
- **Amend ADR-081** (chardevice config.lock substrate sweep): add the Phase-1 finding that
  a deploy-time host sweep cannot prevent a *per-session* bwrap mask (so the char-device
  recurs, now benignly post-#6183), and that the durable prevention locus is the bwrap
  config (`agent-runner-sandbox-config.ts`), tracked on #5934. Amendment, **no new ordinal**.
- **Cite ADR-098** (git-surface topology, authored by #6183) as the canonical non-bare
  model; this plan makes no decision that diverges from it. No new ADR minted.

### C4 views
Checked all three model files (`model.c4`, `views.c4`, `spec.c4`) for external
actors/systems/relationships this change could add. This is an internal shell-script
hardening + telemetry sentinel on an **already-modeled** container (the agent sandbox /
git-worktree surface). No new external human actor, no new external system/vendor, no new
data store, no changed actor↔surface access relationship. **No C4 impact** — the agent
sandbox and its git-surface are already represented; the new sentinel is a log line, not a
new element or edge. (To be re-confirmed by reading the three `.c4` files at /work per the
completeness mandate; if ADR-081's substrate is under-modeled, add the sweep/telemetry edge
then.)

### Sequencing
No soak-gated migration; the ADR-081 amendment describes present state and ships with the PR.

---

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** carry-forward (headless plan; CTO lens applied inline)
**Assessment:** Pure plugin-script + telemetry + docs change on the agent-sandbox surface.
Core risk is a false-positive masked-target detection on the worktree-creation critical
path (mitigated by Option-A fail-loud symmetry + T22 regression lock). No infra
provisioning, no new vendor, no new secret. IaC gate (2.8) does not fire — the durable
bwrap-config change is deferred to #5934 and is a code edit to an existing provisioned
surface, not new infrastructure.

### Product/UX Gate
**Tier:** NONE — no user-facing surface; internal tooling/observability change. No file in
`## Files to Edit` matches a UI-surface glob.

---

## Files to Edit
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — D1 guard + sentinel in `atomic_git_config`.
- `plugins/soleur/test/worktree-manager-atomic-config.test.sh` — D2 tests T20–T22.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — add `SOLEUR_GIT_CONFIG_TARGET_MASKED` to **both** `MARKER_RE` (line ~48, the ingest allowlist — without this the line is never mirrored to Better Stack) **and** `WEDGE_RE` (line ~57, wedge-vs-DIAG classification → paged). **Deepen-catch:** the two-regex structure means adding to WEDGE_RE alone is a silent no-op; MARKER_RE is the gate.
- `apps/web-platform/test/git-lock-marker-telemetry.test.ts` — cover the new sentinel mirror.
- `knowledge-base/engineering/architecture/decisions/ADR-081-chardevice-config-lock-substrate-sweep.md` — amendment.
- `knowledge-base/project/specs/feat-one-shot-5934-config-target-masked-wedge/decision-challenges.md` — stale-premise User-Challenge (new).

## Files to Create
- `decision-challenges.md` (above) — the only new file.

## Open Code-Review Overlap
None found (no open `code-review`-labelled issue names these paths; to be re-verified at
/work with the `gh issue list --label code-review` + `jq --arg` two-stage form).

---

## Test Scenarios
1. **T20** target = char device → pre-D1 generic failure; post-D1 distinct `SOLEUR_GIT_CONFIG_TARGET_MASKED` + no `mv`.
2. **T21** target = bind-mountpoint → same sentinel (privilege-aware skip if CI can't `mount --bind`).
3. **T22** `config.lock` = char device, `config` = regular → routes around (no sentinel) — observed-case regression lock.
4. Telemetry mirror unit test: `git-lock-marker-telemetry.test.ts` classifies the new sentinel as WEDGE (paged), not DIAG.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/`TBD`/placeholder, or omits the
  threshold, fails `deepen-plan` Phase 4.6 — this one is filled (threshold: single-user incident).
- **Do NOT let D1 over-trigger on the observed `config.lock`-masked case** — T22 is the
  guard; the masked node is the LOCK, the target `config` is a regular file, and the
  existing lockless routing must remain untouched.
- **Do NOT re-open the falsified layer.** If a reviewer asks to "also fix line 492 while
  we're here," decline: zero telemetry events, guarded by the non-bare early-return, and
  #6183 fixed the real path. Adding a patch there is the 7th blind patch this diagnosis exists to prevent.
- The `mknod c 1 3` test may need root in some CI runners; mirror the harness's existing
  privilege-aware skip pattern and keep the symlink-to-`/dev/null` arm as the portable
  load-bearing assertion.
