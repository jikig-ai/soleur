# Plan Review Record — 2026-10-11

Plan: `knowledge-base/project/plans/2026-10-11-fix-sandbox-shim-procfs-under-masked-proc-plan.md`
Threshold: `single-user incident` (5-agent panel + named panel prescribed by plan-review SKILL.md)

## Harness note (limitation, disclosed)

The plan-review skill prescribes a parallel Task-agent fan-out
(DHH + Kieran + code-simplicity baseline; architecture-strategist +
spec-flow-analyzer at single-user threshold; named panel
CTO/CPO/CMO/UX by independent relevance read). **This harness exposes
no Task/subagent tool**, so the fan-out could not be spawned. The
lenses below were applied inline by the planning agent — a weaker
guarantee than independent reviewers; `soleur:review` and the issue's
mandated CTO+CLO seats remain the binding review. `soleur:deepen-plan`
runs next in this pipeline and provides the second structural pass.

Reviewed-Coverage: inline-single-agent (fan-out unavailable)

## Standing check — AC vs concurrent processes

`cq-ac-must-not-depend-on-concurrent-sessions` applied to every AC:

- AC1 (fixture/payload argv through shim — deterministic): PASS
- AC2 (in-image spawn on pinned bubblewrap — deterministic; a sibling
  docker run cannot flip it): PASS
- AC3 (classifier mutation pinned in unit suite): PASS
- AC5 (ADR/runbook/register files + review-seat records in PR): PASS
- AC6 (`git grep -nE 'security-opt[= ]+systempaths' apps/web-platform/`
  — executed at plan time 2026-10-11, rc=1/zero hits; scoped to the
  `--security-opt` token so prose mentions cannot false-fail): PASS
- AC7 (dispositioned comment + tracked issue #10045): PASS
- AC8 (test suite re-measure): PASS
- AC9 (ratchet constant +1): PASS
- AC4 (post-merge deploy-state read): environment-dependent by nature;
  it lives in `### Post-merge (deploy)` and is not a code gate — the
  standing check targets pre-merge criteria. Accepted.

## Lens findings (inline application)

- **code-simplicity (per-mechanism vs requirement):** the two rungs of
  the re-home ladder were each tested against "does a simpler mechanism
  satisfy P3?" — `--ro-bind` of the resolved source covers
  bindable-but-unreadable fds (O_PATH); `--bind-data` covers
  readable-but-non-bindable (memfd). Neither subsumes the other on the
  0.8.0 option set; Phase 0.1 selects which rungs the measured fd
  actually needs. KEEP. The third candidate (`--bind-fd`) was cut —
  unavailable before bwrap 0.10.0, prod is 0.8.0.
- **Kieran (correctness/coupling):** one finding applied inline —
  `add_cmd_fd_refs`-style enumeration must be a substring scan over the
  whole serialized argv, not a whole-token match, or a `/proc/self/fd/N`
  ref embedded inside a `bash -c '…'` string escapes the re-home. Plan
  Phase 0.1 and Guard 1 mutation #2/#3 now carry it. Second finding
  noted for work phase: `--bind-data <N>` reads the fd at bwrap-side fd
  number — the re-home MUST use the post-fd-hygiene number; the spike
  records it.
- **DHH (simplicity/ceremony):** the Phase-0 spike is measurement the
  issue itself demands (the `sdk_noproc` control did not measure the
  production argv) — not ceremony. No cut findings.
- **architecture-strategist (blast radius):** the diff is confined to
  shim + canary + tests + records; the fallback arm's blast radius
  (whole-container mask widening) is enumerated in the plan and gated.
  No finding.
- **spec-flow (journey):** spawn → shim rewrite → bwrap mount →
  multicall exec → agent command walked end-to-end; the writer-path gap
  that recurs in this repo's history (a new mechanism never invoked)
  does not apply — the shim IS the spawn path. No finding.
- **Named panel (independent relevance read):** CTO — deferred to
  `soleur:review` (issue mandates the seat on the diff, not the plan);
  CPO — `requires_cpo_signoff` posture already carried; CMO/UX — no
  user-facing or market surface in the file list; none activate.

## Classifier routing

No Taste or User-Challenge findings surfaced → nothing persisted for
the attached "Apply these changes?" gate. The one scope-sensitive
decision (procfs-free rewrite vs `systempaths=unconfined`) is the
issue's own enumerated candidate set, routed to the issue's mandated
CTO+CLO review — operator-routed by the ask itself, not a challenge.

## Literal-command verification (sharp-edge #277)

- `git grep -nE 'security-opt[= ]+systempaths' apps/web-platform/` →
  rc=1, zero hits (ran 2026-10-11 in this worktree).
- Every `knowledge-base/*.md` path cited in the plan exists except
  `…/measurements.md`, which is a Files-to-Create deliverable.
- `npx markdownlint-cli2` on plan + tasks.md → 0 issues.
