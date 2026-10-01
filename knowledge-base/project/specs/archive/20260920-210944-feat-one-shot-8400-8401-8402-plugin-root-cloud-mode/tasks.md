---
title: "Tasks — plugin-root / cloud-mode resolution (#8400, #8401, #8402)"
branch: feat-one-shot-8400-8401-8402-plugin-root-cloud-mode
plan: knowledge-base/project/plans/archive/20260920-210944-2026-09-20-fix-plugin-root-cloud-mode-resolution-plan.md
lane: cross-domain
---

# Tasks

Derived from the finalized (post-review) plan. **Read `## Plan Review Consolidation` first — it is
authoritative where it conflicts with an earlier section.** Phase order is load-bearing: Phase 1
produces the capability token, Phase 2 consumes it; within Phase 2 the harness lands before the
gate; within Phase 3 the guard lands before the sweep.

## Phase 0 — Preconditions

- [ ] 0.1 Read `## Plan Review Consolidation`, `## Guard Contract` and `## Sharp Edges` in full.
- [ ] 0.2 Resolve the two open design questions the panel requires closing **before** RED work:
  - [ ] 0.2.1 `/opt/.devin/plugins` containment under test (consolidation X1) — add an override the
        fences consume and `run_gate` sets, or an AC naming the ambient dependency.
  - [ ] 0.2.2 Fleet block: full recipe vs pointer (consolidation "Recorded, not adopted") — measure
        the per-body context delta × 67 first. Changing this after the sweep is the rework.
- [ ] 0.3 Decide the RESOLVE echo placement and the `devin-cache-nomatch` source value (spec-flow A3).

## Phase 1 — #8400: reap guards (own commit)

- [ ] 1.1 Write the failing suite FIRST. Model on `lease-protects-active.test.sh` for the reap
      fixture and `worktree-manager-safe-branch-sanitization.test.sh` for the `diff`-confirmed
      mutant technique. Prefer extending the former over a tenth `worktree-manager-*` file.
  - [ ] 1.1.1 **Pre-stamp `$(_session_state_root)/reaper-armed`** — without it Test 3 fails and
        Guard 1 rows 1-2 are vacuous (consolidation B6).
  - [ ] 1.1.2 PATH-stub `git` and `gh` so `push origin --delete` / `branch -D` are recorded.
  - [ ] 1.1.3 Assertion floor: `printf >&2` + `exit 1`, counter at the call site, never in `$( )`.
- [ ] 1.2 Lease guard: drop the path conjunct, key on `$safe_branch`, keep the dual key for
      `switch_worktree`'s LEGACY-NESTED FALLBACK (a **live** producer — consolidation B10). Update
      that function's stale "since #7408 that equals the SLUG" comment.
- [ ] 1.3 Recent-commit grace: add the `refs/heads/$branch` arm; `|| true`; inline comment naming
      what it measures and the squash-merge consequence.
- [ ] 1.4 Gate **only** the `reset --hard` on being on `main`/`master`; leave the clean-tree
      `checkout main` + `pull` reachable (consolidation B8).
- [ ] 1.5 Fold in `git merge-base --is-ancestor` before `git branch -D` (consolidation B4).
- [ ] 1.6 Plant the capability token — no `-v1`; membership-testable value.
- [ ] 1.7 Reword the `:81-84` banner to name branches; carry the remedy on the **stdout** sentinel
      and correct it for marketplace users (consolidation CPO-C1b).
- [ ] 1.8 Emit `SOLEUR_WORKTREE_REAPED …` unconditionally per reap, with a recovery pointer.
- [ ] 1.9 `set -euo pipefail` discipline, six sites; note C5 (detached HEAD → `HEAD`, rc 0).
- [ ] 1.10 Sentinel dispositions in `git-lock-marker-telemetry.ts` (consolidation B5).

## Phase 2 — #8401: resolver + capability gate (own commit)

- [ ] 2.1 **Harness first:** rewrite R9's per-gate predicate; add R5d and R11 RED; give `mk_root` a
      present-but-token-less mode; raise `MIN_ASSERTIONS`. Do **not** add R5e; do **not** touch
      `mk_decoy_root` (consolidation C1).
- [ ] 2.2 Capability gate, narrowed to `SRC = devin-cache`, path-pinned, nested inside the existing
      `[ -f ]`; must NOT take `git worktree list` or the `.mcp.json` restore with it (FR8d).
- [ ] 2.3 Extend the feature-detect to the classifier, or state and defend the acceptance
      (consolidation B3 — the dispatch **decision chain**, not just the dispatched artifact).
- [ ] 2.4 Move the Devin cache arms inside the resolver anchors, byte-identical across three fences.
- [ ] 2.5 Add the `reaper-capability-unverified` row to `go.md`'s operator marker list; correct the
      `source=none` bullet that Phase 2 falsifies.
- [ ] 2.6 Amend ADR-179 as item **A16**: both grounds, what closed each, the interceptor-vs-AP-025
      justification, the token's decay + renewal discipline, the `head -1` residual, the TOCTOU
      note, and why three fences exist.

## Phase 3 — #8402: cohort sweep

- [ ] 3.1 **Commit 1:** strengthen `devin-cloud-mode.test.ts` — content assertions, derived negative
      scan (pattern assembled from fragments, no allowlist), planted-positive self-test,
      non-vacuity floor calibrated on the **71**-file derived population, derived marked-set check.
- [ ] 3.2 **Commit 2a:** canonical block + the 67-file mechanical marker sweep.
- [ ] 3.3 **Commit 2b:** the three bespoke non-marker sites (INSTRUCTIONS.md paragraph rewrite,
      plugin `AGENTS.md` pointer, identity-keyed `precommit-guard.sh` resolution).
- [ ] 3.4 **Commit 2c:** `work/SKILL.md`'s commit backstop — close **both** fail-opens
      (consolidation B9).
- [ ] 3.5 Never push with commit 1 at the tip.

## Phase 4 — Records and scope-outs

- [ ] 4.1 C4: both edge descriptions **and** the falsified element description at `model.c4`
      (`session-state.sh` "gates worktree reaping"); run `c4-count-parity`, `c4-code-syntax`,
      `c4-render`.
- [ ] 4.2 `scripts/test-all.sh` scripts-shard comment 21 → 22.
- [ ] 4.3 File the scope-outs: `[gone]`-force-delete (if not folded), `cleanup_orphan_worktree_dirs`,
      `precommit-guard.sh` outside `GATE_SCRIPT_RE`, the plain-clone residual (CPO-C2), the
      `sync-cloud-mode-block.sh` generator, the threshold-taxonomy inversion.
- [ ] 4.4 PR body: `Closes #8400`, `Closes #8401`, `Closes #8402`; the torn-install behaviour change;
      the shape-check-not-authentication scope note **bound to generated copy** (CPO-C3); the
      `reset --hard` justification; the named residual.
