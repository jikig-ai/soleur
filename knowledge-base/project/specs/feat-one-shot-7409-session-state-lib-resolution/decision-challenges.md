# Decision challenges — feat-one-shot-7409-session-state-lib-resolution

Per ADR-084, decisions tagged **taste** or **user-challenge** are surfaced, never silently applied. This plan ran **headless** inside a one-shot pipeline, so the interactive confirmation gate could not run. `/ship` renders this file into the PR body and files it as an `action-required` issue.

Plan: `knowledge-base/project/plans/2026-08-10-fix-session-state-lib-plugin-resolution-plan.md`
Issue: #7409

---

## DC-1 — Split into two PRs instead of one

- **Class:** taste
- **Raised by:** CTO domain review (plan Phase 2.5)
- **Challenge:** Ship the pure `git mv` + repo-consumer repoint as PR 1 (small, byte-identical, hours), and the SKILL.md resolution chain + marketplace-layout fixture as PR 2 (medium, days). PR 2 carries the actual design risk and deserves its own review.
- **Plan decision:** **one PR.** Rationale (plan R-1): a marketplace user reaches `worktree-manager.sh` only through a `SKILL.md` invocation, so a move-only PR would close #7409 without fixing it for the affected population. Byte-identity is preserved at **commit** granularity instead (Phase 1.3 + AC16).
- **If the operator prefers the split:** Phase 3 + Phase 5.1 move to a follow-up, and **#7409 must stay open** until that follow-up merges. The move-only PR must then use `Ref #7409`, not `Closes #7409`.

## DC-2 — Record as an ADR-093 amendment rather than a standalone ADR

- **Class:** taste
- **Raised by:** CTO domain review
- **Challenge:** This resolves part of ADR-093's own declared residual class (#6222); a sibling ADR fragments the anchoring doctrine.
- **Plan decision:** **standalone ADR-175 with a bidirectional cross-reference.** ADR-093 is about SDK plugin-source *trust*; ADR-175 is about *where a shared bash library lives and how it resolves on CLI installs*, and carries its own alternatives table (move / duplicate+drift-gate / fallback-chain-only). #7409 also explicitly requests an ADR. Both documents are edited in this PR, so the doctrine stays navigable either way.

## DC-3 — Destination: `hooks/lib/` vs `scripts/` — RESOLVED BY SYNTHESIS

- **Class:** taste (resolved; no operator decision needed)
- **Raised by:** CTO (`hooks/lib/`) vs scoped advisor consult (`scripts/`), then adjudicated by architecture-strategist plan-review.
- **What happened:** the first draft chose `plugins/soleur/hooks/lib/` on two CTO-supplied grounds. Architecture review verified **both were factually wrong**:
  1. `plugins/soleur/AGENTS.md:182` ("all files in `scripts/` are README-linked") sits under `## Skill Compliance Checklist` → `### Reference Links` — it governs a *skill's own* `skills/<name>/scripts/`, **not** top-level `plugins/soleur/scripts/`. Ground void.
  2. The draft dated `plugins/soleur/lib/` to 2026-08-09; actual creation is **2026-07-11** (`766199eda`) — a month old, not one day. Ground void.
- **Resolution: `plugins/soleur/scripts/lib/session-state.sh`** — a third option satisfying both parties. It sits in the plugin's established sourceable-shell-helper home (answering the advisor's cohesion objection), and the `lib/` segment keeps the ADR-156 A1 carve-out `*/lib/session-state.sh` matching with **zero edit** (preserving the one CTO ground that survived). `<x>/scripts/lib/` is an established repo pattern (`scripts/lib/`, `apps/web-platform/scripts/lib/`). The test goes to `plugins/soleur/test/` (auto-globbed) either way.
- **No operator action required** — recorded because the destination changed after the first draft.

## DC-5 — `acquire_lease` must not degrade open silently (spec-flow reversal)

- **Class:** user-challenge (reversed a decision the plan had already restated once)
- **Raised by:** spec-flow-analyzer (P0-3)
- **Challenge:** the plan grouped `git-worktree/SKILL.md:320`'s `acquire_lease` with the two `release_lease` sites and gave all three a silent `|| true`. But `release_lease` failing is inert (leases expire), whereas **`acquire_lease` failing means the worktree runs unleased** — which, *after this PR*, is precisely the state a sibling `cleanup-merged` will reap.
- **Plan decision:** **adopted.** `acquire_lease` is reclassified onto the destructive side of the gradient: it still degrades open (there is nothing else to do) but emits `reason=worktree-UNLEASED-and-reapable` prominently rather than failing silently.
- **Related, and the more serious half:** spec-flow observed that this PR **arms the reaper** for the marketplace population — pre-fix they could never reap anything, post-fix an unrecoverable operation goes live for them for the first time. The plan now carries a dedicated cache-layout refusal test with a mutation arm (T3 / AC5). The operator should know this PR's blast radius is *enabling*, not merely corrective.

## DC-4 — Terminal fallback arm: degrade open, not fail loud

- **Class:** user-challenge (reversed a decision the plan had stated as "not negotiable")
- **Raised by:** scoped strong-model advisor consult
- **Challenge:** The seven SKILL.md sites wrap **advisory, non-destructive** commands (`gh pr merge --squash --auto`, `release_lease`). Hard-failing when the library is unresolvable converts exit 127 into a prettier exit 127 — the marketplace user's merge is still never queued, so it does not fix the population #7409 is about.
- **Plan decision:** **adopted.** Phase 3 arm 4 now emits a loud stdout marker and **runs the wrapped command anyway**, forfeiting only contention protection (the pre-lock status quo). The destructive reap path stays fail-**closed** inside `worktree-manager.sh`, fixed env-independently by P1.
- **Residual the operator should know:** a user running parallel sessions with an unresolvable library can get concurrent merges to main. Bounded by the loud marker; the alternative (hard fail) blocks the merge entirely for every installed user.

---

## Open measurement that gates two of the above — SETTLED AS "STILL CONFOUNDED", AND IT GATES NOTHING

**Phase 0.2** must settle whether `CLAUDE_PLUGIN_ROOT` is injected for **cache-served** plugin skills. The plan's reading (UNSET) was taken from a **repo-served** skill and is confounded — both copies are installed on the author's machine. The outcome determines Phase 3's arm count and whether Deferral 1 (the wider 21+-site `${CLAUDE_PLUGIN_ROOT:-…}` defect) is filed at all.

### Verdict at /work time (2026-08-10) — recorded so the next planner does not re-litigate it

**Re-measured:** `${CLAUDE_PLUGIN_ROOT:-UNSET}` in this session's Bash env → **`UNSET`**. **The confound is NOT resolved by that reading.** This one-shot run was itself repo-served (its skill preamble reads `Base directory: <repo>/plugins/soleur/skills/one-shot`), which is the exact tell the plan's Sharp Edges names. A repo-served measurement says nothing about the cache-served case, and inside this repo the repo copy wins, so the cache-served path is not reachable from here without an install-only checkout. Reporting `UNSET` as the answer would be restating the confounded measurement with more confidence, not settling it.

**Deferral 1: NOT FILED.** Filing it requires the premise "UNSET for cache-served skills", which remains unmeasured — filing on a confounded reading would put a claim in the backlog that nobody verified. The residual class it belongs to is **already tracked in #6222**, so nothing is lost by not opening a second issue for an unproven member of it.

**Why this genuinely gates nothing in this PR**, as the plan predicted:

1. **P1 reads no environment variable at all.** `worktree-manager.sh` resolves `$SCRIPT_DIR/../../../scripts/lib/session-state.sh`. The destructive reap path's protection is correct by construction in both branches of the unmeasured question — which is *why* the resolution order was inverted away from the issue's proposed `CLAUDE_PLUGIN_ROOT`-first chain.
2. **P2's committed artifact is byte-identical either way.** `${CLAUDE_PLUGIN_ROOT:-<anchor>}` is correct whether the variable is set or unset; that is the point of the default arm.
3. **Verified end-to-end regardless:** the anchor hop was exercised against a real cache-only fixture from a non-Soleur cwd (scenario 10 / T3b), and emits `SOLEUR_WORKTREE_LEASE_LIB_OK`. Coverage of the hop no longer depends on knowing the answer.

**Deferral 2 (`freeze-lock.sh:37` depth coupling): NOT FILED — triaged inline, and it splits into two halves that deserve different answers.**

- *The depth-coupling half is not a defect.* `.claude/hooks/lib/freeze-lock.sh:38` walks `../../..`, which resolves to the repo root correctly from its own location. It contains **zero** `session-state` references, so it is not a consumer of the moved library and nothing in this change disturbs it. It would only break if `freeze-lock.sh` itself moved — a hypothetical, not a defect, and filing it would be backlog noise.
- *The orphan-suite half was real, and is fixed inline.* `.claude/hooks/lib/freeze-lock.test.sh` (13 assertions) had never gated CI, by exactly the R6 mechanism: shell globs do not cross `/`, so `.claude/hooks/*.test.sh` never reached `lib/`. Measured against **every** `*.test.sh` under any `lib/` in the repo, it was the **only** remaining orphan — `scripts/lib/` and `apps/web-platform/scripts/lib/` are already globbed. The fix is one line in `scripts/test-all.sh`, far under the cost-of-filing threshold (≤100 lines, ≤4 files), so deferring it would have been the more expensive choice.

**Net issue flow for this PR: closing 1 (#7409), filing 0 → net −1.**
