# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-13-fix-zot-mirror-large-layer-upload-timeout-plan.md`
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. All gates pass: `lint-guard-contract` (3 entries), `lint-infra-no-human-steps`, the
4.6/4.7/4.8/4.55/4.10/4.11 deepen-plan halts, cited rule IDs active, prescribed labels exist.
Two unresolved KB citations are intentional (ADR-189 is to be created; `spec.md` declared absent).

### Decisions
- **Cause measured, not inherited.** zot v2.1.20 ships `ReadTimeout`/`WriteTimeout` = 60s. A 703 MB
  layer needs 11.73 MB/s sustained or it dies mid-`PATCH`; zot 500s, deletes `.uploads/`, client
  sees `connection reset by peer`. Reproduced off-box on a local docker bridge with Cloudflare
  absent — the tunnel is exonerated and shrink-the-layers is refuted (the 272 MB layer failed at
  the same wall: a time wall, not a size wall).
- **Three inherited premises refuted by measurement.** (1) No restart loop: `zot_restarts=0` across
  the failure window, `zot_uptime_s` 85843 → 86143 monotonic, no restart in 48h. (2) `pcent=12`,
  not 100. (3) Upstream zot#4235 does not apply on the current pin — gc completed for
  `soleur-web-platform` at 20:01 and 21:01.
- **`SOLEUR_ZOT_DISK` was never dark** — 36 rows existed in the window the release run reported
  empty. Reclassifies the secondary finding from a channel defect to a **consumer** defect.
- **Does not close #7341; files a distinct issue.** #7341's closure is mechanised on a fill-rate
  slope by `zot-fill-rate-7341.sh`; a timeout that consumes no disk cannot satisfy it. The two
  refutations go back as a comment. The `.uploads/` link is deliberately not overclaimed — zot
  *succeeds* at cleanup on the measured path.
- **Fix at the origin (zot config), not the client or the topology.** Both deadlines must move
  together: `readTimeout` alone yields a zot-side `202` with no client response — a split-brain
  strictly worse than today's honest 500. `1800s` is bounded above by `gcDelay`, or gc reclaims
  in-flight upload staging.
- **Build the dispatcher rather than book an operator step as automation.**
  `registry-host-replace` is `workflow_dispatch`-only and nothing fires it; a draft AC asserted
  otherwise and passed `lint-infra-no-human-steps` only by containing no actor token.
- **Narrow the cap-exempt widening to the `/blobs/uploads/` pairing.** Exempting all 5xx would let
  health-probe traffic crowd panic traces out of a shared 17-slot lane, reinstating the #7444 R12
  defect one layer down.
- **Excluded "the next release succeeds" as an acceptance criterion** despite a reviewer
  recommending it lead the section — at a ~1-in-13 base rate it passes 92% of the time unfixed,
  and merging fires a release against the still-un-replaced host.

### Scope corrections the planner made to its own first draft
- Pipeline is **intermittent** (~1 in 13; a release succeeded at 21:54:00Z), not hard-blocked.
- The retry loop is **not** futile — it clears a second sub-mode (`unexpected EOF`) this plan
  explicitly does not claim to fix.
- Chokepoint retargeted: `scripts/zot-mirror-diagnosis.sh` is **not on the copy path**; the live
  defect is one unconditional line in `degraded()`.

### Collision re-probe (post-planning, per the #7247 lesson)
- Plan frontmatter: `issue: 7341`, `closes: null`, `refs: [7341, 7456, 7247, 7516]`.
- `closes: null` ⇒ no new work-target collision by construction.
- #7456 OPEN (registry follow-ups incl. rate-cap retune) — this plan partially touches that scope
  via the cap-exempt narrowing; not a duplicate.
- #7247 CLOSED — contextual citation only.
- #7444 MERGED — predecessor whose R12 defect the cap narrowing avoids reinstating.

### Components Invoked
`soleur:plan`; `soleur:plan-review`; `soleur:deepen-plan`; agents `repo-research-analyst`,
`learnings-researcher`, `engineering:cto`, `dhh-rails-reviewer`, `kieran-rails-reviewer`,
`code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`;
`scripts/betterstack-query.sh` (self-pulled telemetry), `gh` CLI, `lint-guard-contract.py`,
`lint-infra-no-human-steps.py`, `registry-userdata-budget.sh`.
