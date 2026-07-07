---
title: "fix(worktree): non-bare Concierge wedge — stop ensure_worktree_identity clobbering the host-seeded owner identity"
issue: 6184
deferred_followups: [6186]
branch: feat-one-shot-worktree-config-lock-wedge
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: bug-fix
created: 2026-07-07
---

# 🐛 Fix the recurring non-bare Concierge worktree-creation wedge

Tracking issue: **#6184** (NOT #4826 — see Research Reconciliation). Closes #6184. Deferred hardening: #6186.

## Enhancement Summary

**Deepened on:** 2026-07-07. **Method:** evidence-first (Better Stack telemetry + local RC=255 reproduction) → escalated 5-agent plan-review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow) + CTO + learnings-researcher → deepen-plan gate + citation verification.

### Key improvements over the initial hypothesis
1. **Root cause corrected twice by evidence.** The task-brief hypothesis (bind-mounted-regular lock / `_config_lock_wedged` mis-classification) and the coordinator's course-correction (sweep / `git worktree add` resilience) were both refined: telemetry shows `type=chardevice`, `git worktree add` succeeds, and the real failure is the **identity-authority inversion** (`Dockerfile:212` bot global vs `workspace.ts:246` owner local) making `ensure_worktree_identity` clobber the owner → EEXIST on the masked lock.
2. **Primary fix flipped off "route the write" (Layer A)** — arch-strategist proved it would "succeed" at misattributing commits to `github-actions[bot]`. New primary: respect the host-seeded owner identity.
3. **Scope trimmed** — Phase 3 write-in-place dropped (unanimous); detector unification deferred to #6186.
4. **Sentinel emitter split** fixed (spec-flow + Kieran P0); `set -e` disarm-inside-`if!` trap fixed (Kieran HIGH); AC greps de-vacuum'd (Kieran MEDIUM ×2).
5. **Root-of-recurrence docs added** (coordinator): canonical ADR-099 git-surface-topology + budget-gated AGENTS caveat.

### Verification performed (deepen-plan)
- All halt gates pass: 4.6 User-Brand Impact ✓, 4.7 Observability 5-field (no-SSH) ✓, 4.8 no PAT-shaped vars ✓, 4.9 N/A (no UI surface).
- All cited learning paths (7), rule-ids (8), ADR-081 + postmortem resolve on disk (ADR-099 is a Files-to-Create).
- Precedent-diff (4.4): the set-when-absent write reuses the established `atomic_git_config` lockless pattern (#5932) — no novel pattern-bound shape. Not a scheduled job; no network-outage/downtime trigger.
- `git config --local ≡ --file <common-dir>/config` on both `worktreeConfig` on/off — Kieran empirically re-confirmed on git 2.53.

### New considerations surfaced (deepen-plan deliverables → deepen/work + follow-ups)
- Bare-CLI-regression check for "don't clobber local" (deepen-plan precedent-diff D.1).
- Layer-B host-side option: remove/replace the `Dockerfile:212` bot global or set sandbox `--global` = owner at provision (audit `push-branch.ts`/`inflight-checkpoint.ts` reliance) — deepen-plan D.2; may spawn its own issue.
- AGENTS `B_ALWAYS` at 22995/23000 — the core-rule caveat must be net-byte-neutral or paired with a loader-class-fit-verified `wg-*` demotion.

## Overview

`worktree-manager.sh create`/`feature` fails in the Concierge/agent-sandbox web environment, blocking every `/soleur:one-shot` and `/soleur:go` autonomous run. Six prior rounds hardened the **bare-repo `ensure_bare_config`** path and the **sweep**, yet the wedge survived — because the actual failing path is a different, un-instrumented code path on the NON-bare layout, and it is failing for a reason the prior rounds never suspected: an **identity-authority inversion**.

**Root cause (production-evidence-confirmed + locally reproduced + 5-agent-panel-verified):**

1. The Concierge workspace is a **non-bare** `git clone --depth 1` (`core.bare=false`, has `.git/`). `ensure_bare_config` runs the sweep then returns early at the non-bare guard (`worktree-manager.sh:478`) — `atomic_git_config`/`_config_lock_wedged` are never reached. `git worktree add` then succeeds (a non-bare add writes no shared config; `worktree-config-seed.ts` itself states add "works natively with ZERO shared-config surgery"; Kieran empirically re-confirmed `--local` from a linked worktree targets the common config on both layouts).
2. `.git/config.lock` in the sandbox is a **character-device /dev/null mask** (`type=chardevice rdev=1:3 mount=none`, Better Stack 2026-07-07) — a **deliberate per-session bwrap git-config-RCE guard** (ADR-081), not a filesystem residual.
3. The sandbox image bakes a **global** identity `github-actions[bot]` (`apps/web-platform/Dockerfile:212-213`). The host seeds the **local** workspace config with the per-workspace **owner** identity (`apps/web-platform/server/workspace.ts:236/246`). So in-sandbox: **global = bot, local = owner.**
4. `ensure_worktree_identity` (`worktree-manager.sh:600-619`) was designed for the **bare CLI dev repo**, where the bare repo carries a bot local and the operator's `--global` is the real human — so it **forces global over local**. On Concierge that topology is **inverted**: it tries to overwrite the correct **owner** local with the **bot** global via a raw `git config --local user.email/name` write (615-616). That write locks the shared `.git/config` → `O_CREAT|O_EXCL` on the masked `config.lock` → **EEXIST** (`could not lock config file …/.git/config: File exists`, RC=255) → `set -euo pipefail` aborts `create` at the bare call sites (1011/1097). Reproduced locally at RC=255; `--local` confirmed to target `rev-parse --git-common-dir`.

**Two consequences make the naive fix wrong:** (a) the EEXIST is a plain-git error, not a `SOLEUR_GIT_LOCK_*` marker, so it was invisible to Better Stack — which is why six rounds missed it; (b) **the wedge is accidentally protective** — the only thing the write would accomplish if it succeeded is misattributing the user's commits to `github-actions[bot]`. Therefore the fix is **NOT** to route the write through `atomic_git_config` (that "succeeds" at corrupting attribution). The fix is to **stop clobbering the authoritative host-seeded owner identity**, unblocking creation AND fixing a latent misattribution bug in one move.

This is a bug fix on an existing surface. No new dependency, no new infrastructure.

## Research Reconciliation — Spec vs. Codebase

Two premises were supplied (the task brief's leading hypothesis, and the coordinator's mid-task course-correction). Evidence-first investigation refined BOTH — the discipline (`2026-06-30-verify-the-fixed-code-path-actually-executes...`) that stops a seventh wrong-layer round.

| Premise | Reality (telemetry + code + repro + 5-agent panel) | Plan response |
|---|---|---|
| (Brief) `.git/config.lock` is a **bind-mounted regular file**; `_config_lock_wedged` mis-classifies it → native EEXIST. | Better Stack: `type=chardevice rdev=1:3 mount=none`. `_config_lock_wedged` ALREADY returns wedged for a chardevice; that path is never reached anyway (guard returns early on non-bare). | Detector unification is real but latent → **deferred to #6186**, not the fix. |
| (Coordinator) Bind-mounted regular lock whose `rm` returns EBUSY; fix belongs in the **sweep** / making **`git worktree add`** resilient. | Telemetry shows chardevice `errno=none` (the sweep never `rm`s a chardevice). Local repro: **`git worktree add` SUCCEEDS**. The failure is the **subsequent identity write**, not add and not the sweep. | Fix targets `ensure_worktree_identity`, not the sweep or `git worktree add`. |
| (Coordinator) Investigate `worktree-config-seed.ts` — it may mask `.git/config`. | Read in full: it only **unsets** `extensions.worktreeConfig` (heals the #6064 seed regression). Does not create the mask, does not seed identity. | Not the cause; cited for the non-bare model it documents. |
| (Both) The fix is a lock/mask-handling change. | The mask is a red herring. The write **should not happen at all** — it clobbers the owner identity with the sandbox bot global (`Dockerfile:212` vs `workspace.ts:246`). | **Primary fix flips** to "don't clobber a valid host-seeded local identity." |
| (My own v1) Route the identity write through `atomic_git_config` (Layer A). | arch-strategist: that "ships a latent wrong-author write that succeeds — worse than a loud wedge." Confirmed: global is `github-actions[bot]`. | **Layer A rejected as primary;** kept only as robustness for the genuine set-when-absent case. |

**Premise Validation note.** Issue #4826 was NOT fetched/scoped (brief: unrelated P3 nav-rail). Fresh tracking issue #6184; deferred hardening #6186. **Caveat (Kieran):** `#4826` is also woven through the host-side worktree-config-heal saga as an umbrella reference AND a real nav-rail test cites it — so the citation surface is broader and more ambiguous than "all mis-linked." Phase 3 therefore corrects only the **wedge-diagnosis** citations in the files this PR already edits, and does NOT sweep the host-side-heal-saga citations (unverifiable without fetching #4826, which the brief forbids). Scope is de-claimed accordingly.

## Fix-Layer Decision

The durable direction (learning `2026-07-05-config-lock-mask-is-sdk-bwrap...`) is to eliminate in-sandbox config writes rather than fight the mask. The corrected primary fix **aligns** with that: it makes the write unnecessary by respecting the host-seeded owner, instead of routing a (wrong) write around the RCE-guard mask.

- **PRIMARY (Phase 1) — respect the host-seeded owner:** `ensure_worktree_identity` treats a present, non-empty **local** identity as authoritative and does NOT overwrite it. On Concierge the worktree inherits the owner identity from the host-seeded shared config → no write → no wedge → correct attribution. On the bare CLI dev repo with no local identity it still sets from global (via the robust path below). Only behavior change: the "local present AND ≠ global" case now keeps local — which is what also fixes the misattribution.
- **ROBUSTNESS — set-when-absent still routes through `atomic_git_config`:** when local IS absent and we set from global, route that write through `atomic_git_config` against the resolved common-dir config so a masked `config.lock` cannot wedge that path either. `user.*` is not an RCE-relevant key; Phase-1 incremental RCE surface is nil (arch-strategist).
- **DEEPEN-PLAN deliverable (identity authority):** the deeper host-side option — remove/replace the `Dockerfile:212` bot global (footgun) or set the sandbox `--global` to the workspace owner at provision so `ensure_worktree_identity`'s guard is a guaranteed no-op. Trade-off: bare-CLI regression + blast radius (audit whether anything relies on a global identity existing; `push-branch.ts`/`inflight-checkpoint.ts` set their own author, so the bot global may be unused for user commits). deepen-plan + architecture adjudicate whether to also land it; if deferred, it spawns its own issue.

## User-Brand Impact

**If this lands broken, the user experiences:** every autonomous `/soleur:one-shot` and `/soleur:go` run in Concierge continues to abort at worktree creation — the product's core promise is dead for that user's workspace. A *wrong* fix (Layer A) would instead silently mis-author the user's commits as `github-actions[bot]` — a subtler brand harm (their git history lies).

**If this leaks, the user's data is exposed via:** N/A — no user data read/written. New telemetry is device/path forensic only, already scrubbed by `git-lock-marker-telemetry.ts`. **Constraint (Phase 2):** the sentinel must never emit the `user.email`/`user.name` values.

**Brand-survival threshold:** `single-user incident` — sixth recurrence of a full-workspace outage; `requires_cpo_signoff: true`. `user-impact-reviewer` at review; escalated 5-agent plan-review + deepen-plan triad mandatory (plan-review already run — see Domain Review).

## Hypotheses (evidence-ranked)

1. **CONFIRMED (mechanism + trigger observed) — identity-authority inversion.** global=`github-actions[bot]` (Dockerfile:212), local=owner (workspace.ts:246), so `ensure_worktree_identity:614` guard passes and 615-616 fire → EEXIST on chardevice `config.lock` → RC=255 abort. Both the mechanism (local RC=255 repro) AND the trigger precondition (global set ∧ global≠local) are grounded in committed code, not inferred.
2. **REAL but latent → #6186 — detector disagreement** (bind-mounted-regular / EBUSY-on-rm). Not the current signature.
3. **REJECTED — Layer A (route the write).** Succeeds at writing bot-over-owner (misattribution).
4. **REJECTED — sweep / `git worktree add` fix.** add succeeds; sweep never rm's a chardevice.
5. **REJECTED — write-in-place fallback / config-itself-a-mountpoint.** Unobserved (`mount=none`); a non-atomic rewrite of the shared multi-key config is more dangerous than the wedge, and a `/dev/null`-target `cat >` returns 0 while silently discarding (arch). A confirmed-mountpoint rename failure fails loud instead.

## Implementation Phases

### Phase 1 — Primary fix: `ensure_worktree_identity` respects the host-seeded local identity (RED → GREEN)

- **RED first:** T14 (Phase 4).
- Rewrite the logic (`:600-619`): read the worktree's local identity first. **If a non-empty local `user.email` AND `user.name` are present, `return 0` without writing** (the seeded owner is authoritative). Only when local identity is absent, set it from the global — routing THAT write through `atomic_git_config`.
  - Resolve the shared config absolute: `common_config="$(git -C "$worktree_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/config"` (`--path-format=absolute` load-bearing — bare `--git-common-dir` returns relative `.git`; learning `2026-03-18-git-common-dir-vs-show-toplevel-semantics.md`). If resolution is empty/fails, emit the `common-dir-unresolved` sentinel (Phase 2) and `return 1` — do NOT fall back to `$GIT_ROOT/.git/config` (Kieran: wrong on the bare layout where `$GIT_ROOT` has no `.git/` subdir).
- **`set -e` discipline (Kieran HIGH — mandatory shape):** wrapping the call site `if ! ensure_worktree_identity …` **disarms `errexit` for the whole function body**, so a bare `atomic_git_config …` failure inside would silently fall through to the success `echo` + `return 0` (vacuous success — worse than the wedge). Therefore each write MUST be its own explicit guard:
  ```bash
  if ! atomic_git_config "$common_config" user.email "$global_email" \
     || ! atomic_git_config "$common_config" user.name "$global_name"; then
    echo "SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=native-eexist file=config"   # stdout
    return 1
  fi
  ```
  Correct the rationale in code comments: the wrap matters (a) to give a contextual red error + `exit 1` instead of a bare abort, and (b) precisely because it disarms errexit, forcing these explicit per-write checks — NOT because "an echo wouldn't print" (an `echo` before `return 1` always flushes).
- Wrap BOTH bare call sites (`:1011` create_worktree, `:1097` create_for_feature) in `if ! ensure_worktree_identity "$worktree_path"; then <red error>; exit 1; fi`, mirroring the `ensure_bare_config` pattern at 936/1004.
- Rewrite the stale NOTE at `:588-599` — it encodes the inverted bare-repo assumption. Document the non-bare Concierge reality (local = host-seeded owner = authoritative; function no longer clobbers a present local identity).
- **Self-check grep (corrected):** `grep -nE "git (-C [^ ]+ )?config " worktree-manager.sh | grep -vE "(--get|--file|--global|^ *#)"` — the parens are load-bearing; `grep -vE "--get|…"` parses `--get` as an option and errors (Kieran verified on both ugrep and GNU grep).

### Phase 2 — Observability: split-emitter in-sandbox sentinel

- Add a grep-able **stdout** sentinel (stdout has 30d proven Better Stack capture; stderr is invisible under `claude --bg`). **Emitter ownership (spec-flow + Kieran P0):**
  - `ensure_worktree_identity` owns `SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=native-eexist` (its set-from-global write failed) and `reason=common-dir-unresolved`. It emits these itself (it knows the context) — do NOT also emit from inside `atomic_git_config` for the identity path, to avoid the double-marker-with-`TEMP_WEDGED` contradiction spec-flow found.
  - Because `atomic_git_config` collapses several internal failures into one non-zero rc and does not surface git's errno, the caller-side sentinel carries only what it can KNOW: `source`, `reason` (native-eexist vs common-dir-unresolved), and `file`. Do NOT invent an `errno=` field the caller cannot derive (Kieran LOW). If an `rdev=` is wanted, the caller must `stat` the lock itself; otherwise omit it.
- **Precondition marker (arch #6):** when `ensure_worktree_identity` takes the set-from-global branch (local absent → drift detected), emit a **benign DIAG-class** marker regardless of success, so post-deploy telemetry PROVES the path executes in production. A successful respect-local no-op emits nothing (expected).
- Extend `apps/web-platform/server/git-lock-marker-telemetry.ts` `MARKER_RE` to match the new sentinel + the benign DIAG marker, and `WEDGE_RE` to match ONLY the genuine-wedge reasons (`native-eexist`, `common-dir-unresolved`) — NOT the benign precondition marker (else a successful drift-set pages as `wedged=true`/`log.error`). The drift test `git-lock-marker-telemetry.test.ts` **auto-discovers** every `echo "SOLEUR_GIT_*"` literal and requires `MARKER_RE` to match it (Kieran) — so the required change is the `.ts` regex extension; the test then fails CI automatically if a sentinel is unmatched.
- **Delivery-trigger note (code-simplicity):** this `apps/web-platform/**` edit is ALSO what fires the path-filtered image rebuild that ships the plugin script (ADR-080 / #5880 trap) — load-bearing for delivery, not only observability.
- Affected-surface (Phase 2.9.2): `source=`/`reason=` discriminate the failure modes in one event on the blind surface.

### Phase 3 — Correct the wedge-diagnosis `#4826` citations → `#6184` (scoped, not "all")

Correct only the **wedge-diagnosis** citations in the files this PR already edits:
- `worktree-manager.sh:455, 816-817`; `git-repo-readiness-diag.sh:2, 9`; `worktree-manager-atomic-config.test.sh:249, 250, 262, 270`; `one-shot/SKILL.md:52`; **and** `apps/web-platform/server/git-lock-marker-telemetry.ts:1, 13, 37` + `apps/web-platform/test/git-lock-marker-telemetry.test.ts:1` (edited in Phase 2, they cite #4826 for the same wedge — Kieran).
- Preserve comments that legitimately cite a prior PR number (only the ISSUE reference changes).
- **Explicitly OUT of scope:** the host-side-heal-saga citations in `worktree-config-seed.ts`, `workspace.ts`, `ensure-workspace-repo.ts` and unrelated nav-rail tests — their #4826 linkage is a separate, unverifiable-without-fetching question (brief forbids fetching #4826). Do NOT sweep them; the plan does NOT claim "all #4826 corrected."

### Phase 4 — Tests (RED-first; both layouts)

Extend `plugins/soleur/test/worktree-manager-atomic-config.test.sh` (auto-discovered by `scripts/test-all.sh:204`; `test-helpers.sh`, `cq-test-fixtures-synthesized-only`):
- **T14 (primary — respect owner, non-vacuous):** non-bare + linked worktree; seed the shared config with a **distinctive OWNER identity**; set a **DIFFERENT global** identity; place a non-regular `.git/config.lock` (directory stand-in; char-device variant guarded on `mknod`/root, mirroring Test 9). Assert `ensure_worktree_identity` returns 0 AND the local identity read-back **still equals the OWNER** (NOT the global) — this exercises the exact `local ≠ global` branch that fired 615-616 (Kieran vacuous-green guard). Comment the proxy caveat: the directory stand-in exercises the `O_CREAT|O_EXCL` EEXIST class; the real `rdev=1:3` chardevice node is only exercised under `mknod`/root (spec-flow).
- **T15 (set-when-absent robustness):** non-bare + worktree with NO local identity + a global set + non-regular `config.lock` → identity set from global via `atomic_git_config` lockless path, rc 0, lands in the resolved common config.
- **T16 (set -e ordering, via the real call path):** drive the failure through the **wrapped call site under active `set -e`** (a faithful reproduction of `create_worktree`'s `if ! ensure_worktree_identity`), not the function in isolation (Kieran) — force `common-dir-unresolved`, assert the sentinel is PRINTED, the function returns 1, and the caller emits its red error + non-zero exit.
- **T17 (bare layout regression):** existing bare `ensure_bare_config` flow unchanged (complements Tests 12/13).
- Update the test header comment to the identity-inversion diagnosis.

### Phase 5 — Canonical topology docs (coordinator-directed; Architecture Decision (1)+(3))

- Author `ADR-099-git-surface-topology.md` (three surfaces + the non-bare-guard consequence; cross-link ADR-081 + the postmortem). Provisional ordinal — `/ship` re-verifies against origin/main.
- Amend `ADR-081-chardevice-config-lock-substrate-sweep.md` (`## Decision` + `## Alternatives Considered`) per Architecture Decision (2).
- AGENTS.rest.md `rf-after-merging…`: append the non-bare caveat + ADR-099 pointer (budget-free).
- AGENTS.core.md `hr-when-in-a-worktree…` + `wg-at-session-start…`: add the concise non-bare caveat + ADR-099 pointer, net-byte-neutral (or free room via a loader-class-fit-verified `wg-*` demotion). Run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` and confirm exit 0 BEFORE and AFTER.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — Phases 1, 2, 3.
- `plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh` — Phase 3.
- `apps/web-platform/server/git-lock-marker-telemetry.ts` — Phases 2, 3.
- `apps/web-platform/test/git-lock-marker-telemetry.test.ts` — Phases 2, 3.
- `plugins/soleur/test/worktree-manager-atomic-config.test.sh` — Phase 4 + Phase 3.
- `plugins/soleur/skills/one-shot/SKILL.md` — Phase 3.
- `plugins/soleur/skills/git-worktree/SKILL.md` — Sharp Edge: never re-add a raw `git config` write; identity-authority note.
- `knowledge-base/engineering/architecture/decisions/ADR-081-chardevice-config-lock-substrate-sweep.md` — amendment (Architecture Decision (2)).
- `AGENTS.core.md` — non-bare caveat + ADR-099 pointer on `hr-when-in-a-worktree…` (:35) and `wg-at-session-start…` (:57), **net-byte-neutral or via a wg-* demotion** (Architecture Decision (3); budget-gated).
- `AGENTS.rest.md` — non-bare caveat + ADR-099 pointer on `rf-after-merging…` (:42) (budget-free).

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md` — canonical three-surface git topology (Architecture Decision (1); provisional ordinal).

## Acceptance Criteria

### Pre-merge (PR)
1. Non-bare repo + worktree seeded with a distinctive OWNER identity + a DIFFERENT global + non-regular `.git/config.lock`: `ensure_worktree_identity` returns 0 and the local identity read-back is STILL the OWNER (NOT the global) — T14. (Currently RC=255.)
2. `grep -nE "git (-C [^ ]+ )?config " plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh | grep -vE "(--get|--file|--global|^ *#)"` shows zero raw shared-config WRITE sites bypassing `atomic_git_config` (note the parens — required or grep errors).
3. Both call sites wrap `ensure_worktree_identity` in `if !`; each write inside is its own `if ! … || ! …; then emit; return 1; fi` (no bare write relying on errexit) — T16 drives this through the wrapped call site under active `set -e` and confirms the sentinel survives + graceful non-zero exit.
4. Set-when-absent path writes via `atomic_git_config` lockless branch, lands in the resolved common config — T15.
5. `bash plugins/soleur/test/worktree-manager-atomic-config.test.sh` passes (existing 1–13 + T14–T17).
6. `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts` passes: `MARKER_RE` matches the new sentinel + benign precondition marker; `WEDGE_RE` matches the wedge reasons only (not the benign marker); each `reason=` has exactly one reachable emitter with the correct `source=`.
7. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes.
8. `grep -rn "4826" plugins/soleur/skills/git-worktree/ plugins/soleur/test/worktree-manager-atomic-config.test.sh plugins/soleur/skills/one-shot/SKILL.md apps/web-platform/server/git-lock-marker-telemetry.ts apps/web-platform/test/git-lock-marker-telemetry.test.ts` returns zero — scoped to exactly the files Phase 3 edits (NOT a broader surface; the host-side-heal citations are deliberately out of scope). `knowledge-base/project/{plans,specs}/**` excluded.
9. `bash scripts/test-all.sh` (from a worktree) green for the scripts + webplat shards touched.
10. `ADR-099-git-surface-topology.md` exists, non-empty, states all three surfaces, and cross-links ADR-081 + the postmortem; ADR-081 amended (`## Decision` + `## Alternatives Considered`). C4 syntax/render tests still pass (`apps/web-platform/test/c4-*.test.ts`) — no `.c4` edit, so a no-op check.
11. `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` exits 0 after the AGENTS edits (B_ALWAYS ≤ 23000); all three target rules carry the non-bare caveat + ADR-099 pointer; rule ids unchanged (`cq-rule-ids-are-immutable`); each edited rule body stays one line (`cq-agents-md-why-single-line`).

### Post-merge (operator) — automatable, routed to /ship + postmerge (no manual steps)
10. After the web-platform image rebuild deploys, `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 48h --grep SOLEUR_GIT_LOCK_IDENTITY_WEDGED` shows the benign precondition marker on real creates (proves the path executes) and NO `reason=native-eexist|common-dir-unresolved` on successful runs (read-only; `hr-no-dashboard-eyeball-pull-data-yourself`).

## Observability

```yaml
liveness_signal:
  what: SOLEUR_GIT_LOCK_DIAG (sweep, live) + SOLEUR_GIT_LOCK_IDENTITY_WEDGED (errors) + benign identity-drift precondition marker
  cadence: per worktree-create attempt in the Concierge sandbox
  alert_target: Better Stack ClickHouse (source soleur-web-platform app_container, context=git-lock-marker-telemetry) + Sentry breadcrumb
  configured_in: apps/web-platform/server/git-lock-marker-telemetry.ts
error_reporting:
  destination: Better Stack (pino->journald->vector) + Sentry breadcrumb
  fail_loud: yes — grep-able STDOUT sentinel; mirrored server-side (observe-only, fail-open {})
failure_modes:
  - mode: set-from-global write EEXISTs on masked lock (local-absent branch only)
    detection: SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=native-eexist
    alert_route: scripts/betterstack-query.sh --grep SOLEUR_GIT_LOCK_IDENTITY_WEDGED
  - mode: common-dir unresolved (masked git)
    detection: SOLEUR_GIT_LOCK_IDENTITY_WEDGED source=ensure_worktree_identity reason=common-dir-unresolved
    alert_route: same
  - mode: precondition observed (identity drift → set-from-global branch)
    detection: benign DIAG-class identity-drift marker (proves path executes; NOT a wedge)
    alert_route: same (informational)
logs:
  where: Better Stack ClickHouse (t520508_soleur_inngest_vector_prd_3_logs), 30d+ retention observed
  retention: per Better Stack source config
discoverability_test:
  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_GIT_LOCK_IDENTITY_WEDGED --grep SOLEUR_GIT_LOCK_DIAG
  expected_output: after fix, no native-eexist/common-dir-unresolved on successful creates; the benign drift marker confirms the path fires; a native-eexist line pinpoints a residual wedge with source/reason in one event
```

## Architecture Decision (ADR / C4)

Two ADR actions (coordinator-directed — the ROOT reason this wedged six times is that the git-surface topology was never a canonical loaded fact, so every round mis-targeted it):

**(1) NEW ADR-099 — canonical git-surface topology (provisional ordinal; `/ship` re-verifies against origin/main + sibling-collision sweep).** File `knowledge-base/engineering/architecture/decisions/ADR-099-git-surface-topology.md`. States the three git surfaces as first-class facts + the load-bearing consequence:
- **Server-side git-data:** BARE (`git init --bare`, `/mnt/git-data/repositories/<id>.git`) — `apps/web-platform/infra/git-data-provision.sh`.
- **Agent workspace (where worktree-manager.sh runs):** NON-BARE (`git clone --depth 1`, `/workspaces/<id>`, `core.bare=false`) — `apps/web-platform/server/ensure-workspace-repo.ts`.
- **Local CLI dev:** BARE + worktrees.
- **Consequence:** `worktree-manager.sh`'s `ensure_bare_config` NON-BARE GUARD (`:478`) returns early on the Concierge workspace, so the `atomic_git_config`/`_config_lock_wedged` **bare path never executes there** — the surface every prior round targeted. Cross-link ADR-081 and `knowledge-base/engineering/operations/post-mortems/concierge-worktree-creation-stale-lock-wedge-postmortem.md`.

**(2) ADR-081 amendment (arch-strategist #5).** Records the identity-authority resolution for the non-bare surface: the host-seeded per-workspace **owner** identity is authoritative in-sandbox; `ensure_worktree_identity` must not override it with the image's `github-actions[bot]` global. Amend `## Decision` + add "route-the-write (Layer A)" to `## Alternatives Considered` (rejected: misattributes commits). Extends the existing ADR.

**(3) AGENTS.md caveat (coordinator-directed) — BUDGET-GATED.** The three rules that assert "repo root is bare" are written from the local-dev-bare viewpoint and give no signal that the Concierge workspace is non-bare: `hr-when-in-a-worktree-never-read-from-bare` (AGENTS.core.md:35), `wg-at-session-start-run-bash-plugins-soleur` (AGENTS.core.md:57), `rf-after-merging-read-files-from-the-merged` (AGENTS.rest.md:42). Add a concise non-bare caveat + ADR-099 pointer.
- **Budget reality:** loaded `B_ALWAYS = 22995 / 23000` (measured via `python3 scripts/lint-agents-rule-budget.py`) — only ~5 bytes slack. AGENTS.rest.md is NOT always-loaded → the `rf-after-merging` caveat is budget-free (do the fuller wording there). The two **core** rules are always-loaded → adding bytes breaches the 23000 reject cap.
- **Required approach for the core rules:** either (a) a **net-byte-neutral** edit (tighten existing wording in the same two rules to offset the added pointer; verify `lint-agents-rule-budget.py` exits 0), OR (b) if net-neutral is infeasible, demote ONE `wg-*` rule core→rest to free room — the lint's own WARN names this remedy — with **loader-class-fit verification** (`sed -n '88,126p' .claude/hooks/session-rules-loader.sh`; the demoted rule must not fire on a trigger class where AGENTS.rest.md doesn't load) per learning `2026-05-12-agents-md-trim-loader-class-fit-verification.md`. Respect `cq-agents-md-why-single-line` (one line per rule body), `cq-rule-ids-are-immutable` (no id renames), `cq-agents-md-tier-gate`.

**C4 views: no impact (checked `model.c4`, `views.c4`, `spec.c4`).** External actors — none new (agent sandbox modeled via `claude`/`hetzner`). Vendors — Better Stack already modeled (`model.c4:250`). Data-stores — `.git/config` on host-local worktree NVMe, modeled (`model.c4:170,200`, ADR-068). Access relationships — unchanged. Internal write-path correction + one log marker + docs; nothing crosses the boundary.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO + escalated 5-agent plan-review)

**Status:** reviewed (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer + CTO). Consolidated + applied:
- **Cut Phase 3 write-in-place** — unanimous (DHH/simplicity/arch): unobserved; non-atomic rewrite of shared config worse than the wedge; `/dev/null`-target `cat >` returns 0 while silently discarding. Confirmed-mountpoint rename failure fails loud instead. **Applied.**
- **Defer detector unification to #6186** (DHH/simplicity). **Applied.**
- **Flip primary off Layer A** (arch #3) — routing misattributes to the bot. **Applied** (respect-owner primary).
- **`set -e` disarm inside `if !` wrap** (Kieran HIGH) — each write is its own `if !` guard; bare writes would silently succeed. **Applied** (Phase 1).
- **Broken verification grep** (Kieran MEDIUM) — parenthesize the `grep -vE`. **Applied** (Phase 1 self-check + AC2).
- **`#4826` scope contradiction** (Kieran MEDIUM) — de-claimed "all"; scoped to edited files incl the two `.ts` files; host-side-heal citations explicitly out of scope. **Applied** (Phase 3 + AC8).
- **Sentinel emitter ownership** (spec-flow + Kieran P0) — identity-owned reasons emitted by `ensure_worktree_identity`; no double-emit; no un-derivable `errno=`; benign marker excluded from `WEDGE_RE`. **Applied** (Phase 2).
- **T14 vacuous-green + T16 via real call path** (Kieran) — distinctive owner≠global; T16 exercises the wrapped call site under `set -e`. **Applied** (Phase 4).
- **branch.autoSetupMerge=always edge** (spec-flow minor) — documented in Sharp Edges; default `--no-track` path unaffected.
- **ADR-081 amendment** (arch #5). **Applied.**

### Product/UX Gate

**Tier:** none — no UI-surface file (only `*.sh`, `*.ts`, `*.md`). Skipped.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` scanned for the edited paths — no open scope-out references them; re-run at /work if the backlog changes.)

## Test Scenarios

- Respect owner: non-bare + seeded owner ≠ global + masked lock → rc 0, owner preserved (T14).
- Set-when-absent: non-bare + no local identity + masked lock → set via lockless path (T15).
- set -e ordering via real call path: unresolved common-dir → sentinel printed, rc 1, red error (T16).
- Bare regression: `ensure_bare_config` unchanged (T17 + 12/13).
- Telemetry drift guard recognizes the new sentinel + precondition marker (`MARKER_RE`/`WEDGE_RE`).

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty/thresholdless fails deepen-plan Phase 4.6 — set here.
- **Never re-add a raw `git config` write in worktree-manager.sh.** Every shared-config mutation goes through `atomic_git_config`. (SKILL.md Sharp Edge, Phase 1.)
- **Identity authority is inverted between environments:** on the non-bare Concierge workspace the LOCAL identity is the host-seeded owner (authoritative); on the bare CLI dev repo the operator's GLOBAL is the human. Do NOT re-introduce blanket "force global over local" — it misattributes Concierge commits to `github-actions[bot]`.
- **`if !`-wrapping a function disarms `set -e` inside it** — every write in `ensure_worktree_identity` must be an explicit `if !` check + `return 1`; do not rely on errexit propagation. An `echo` before `return 1` always flushes, so the sentinel is not the reason for the wrap.
- `git config --local` from a linked worktree targets the SHARED common-dir config; `--git-common-dir` can return a RELATIVE path — always `--path-format=absolute`. Do NOT fall back to `$GIT_ROOT/.git/config` (wrong on the bare layout).
- The chardevice `config.lock` PERSISTS after the fix (sandbox substrate owns it). Success = create succeeds and commits stay owner-attributed. Persisting `SOLEUR_GIT_LOCK_DIAG` is expected, not a regression.
- `--update-local-main` + user global `branch.autoSetupMerge=always`: git's own `branch.*` write during `add` could EEXIST on the masked lock. Out of scope (default `--no-track` path is safe); note for future.
- The new sentinel emits ONLY device/path forensic — never the `user.email`/`user.name` values, and no un-derivable `errno=`.
- `#4826`→`#6184`: scoped to edited files only; preserve prior-PR-number comments; do NOT claim "all citations corrected."
- **AGENTS always-loaded budget is at the cap (B_ALWAYS 22995/23000, ~5 bytes slack).** Any addition to AGENTS.md or AGENTS.core.md breaches the reject cap. The core-rule caveat MUST be net-byte-neutral OR paired with a loader-class-fit-verified `wg-*` core→rest demotion. Put the fuller caveat in AGENTS.rest.md (`rf-after-merging`, not always-loaded) and the ADR-099 pointer in core. Verify with `lint-agents-rule-budget.py` (exit 0) before/after.
- **ADR-099 ordinal is provisional.** A sibling PR can claim it during the pipeline (ordinals surface only post-squash on main). `/ship`'s ADR-Ordinal Collision Gate re-verifies against origin/main; if renumbered, sweep the whole feature's artifact set for the old ordinal (`grep -rn 'ADR-099' knowledge-base/project/{plans,specs}/feat-one-shot-worktree-config-lock-wedge/` + the AGENTS pointers + the ADR-081 cross-link).

## Risks & Mitigations

- **Bare-CLI regression from "don't clobber local".** Mitigation: only the "local present AND ≠ global" case changes; common bare-CLI (no local) still sets from global. The rare "bare repo has a bot local" case is a deepen-plan/CPO decision (keeping local is arguably more correct). deepen-plan precedent-diff required.
- **Layer B (host-side global alignment) not landed here.** Mitigation: respect-owner primary already fixes wedge + attribution; host-side removal of the `Dockerfile:212` bot global is a deepen-plan decision (audit `push-branch.ts`/`inflight-checkpoint.ts` reliance first) that may spawn its own issue.
- **Common-dir relative/empty.** Mitigation: `--path-format=absolute`; on failure emit `common-dir-unresolved` + `return 1` (no wrong fallback).
- **Delivery path (plugin-only merges rebuild no image — ADR-080).** Mitigation: this PR edits `apps/web-platform/**`, firing the path-filtered rebuild that ships the plugin script; postmerge confirms via deploy webhook + AC10 telemetry query.
- **Seventh-round risk.** Mitigation: mechanism AND trigger grounded in committed code (Dockerfile:212 + workspace.ts:246) + local RC=255 repro + benign precondition marker to confirm post-deploy — not code-reading alone.
