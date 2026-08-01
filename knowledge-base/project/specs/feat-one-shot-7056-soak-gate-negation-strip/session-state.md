# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-01-fix-ship-soak-gate-matches-token-not-claim-plan.md`
- Tasks file: `knowledge-base/project/specs/feat-one-shot-7056-soak-gate-negation-strip/tasks.md`
- Status: complete
- Scope check: PASS — `git diff <base>..HEAD --name-only` listed only the plan and tasks files. Three-dot and base-SHA diffs agree, so no stale-`origin/main` artifact.

### Errors
- One agent spawn failed on a wrong type path (`soleur:engineering:product:spec-flow-analyzer`); relaunched as `soleur:product:spec-flow-analyzer`. No impact.
- Self-inflicted, caught in-session: the planner's first-draft matcher was a severe recall regression (42/50 → 22/50 against ground truth). Reversed in deepen round 2; the rejected design is retained in the plan rather than deleted.

### Decisions
- **Neither fix option named in #7056 was adopted.** Option 1 (delete the bare `soak` alternative) collapses recall; option 2 (negation strip alone) leaves #7087 unfixed, because a filename is not a negation.
- **Chosen: structural left-delimiter on the bare noun** (`(^|[^[:alnum:]_-])soak`) — which is the whole of #7087's fix — **plus negation stripping applied as a span, not a line drop**, which is #7056's fix. A line drop was measured to swallow real declarations that share a line with a disposition.
- **#7087 is BUNDLED.** Same regex, same two files, same root cause; the fixes compose with no conflict. `Closes #7056` and `Closes #7087` both go in the PR body.
- **The scan is extracted into `scripts/ship-soak-signal-gate.sh`** which owns the regex and every strip, mirroring `scripts/ship-incident-pir-gate.sh`. This retires the byte-identical-by-convention duplication between the hook and `ship/SKILL.md` rather than adding a second parity pin, and it is what makes the behavioural fixture pair possible — the existing test only string-matches Markdown and has never executed the matcher.
- **Acceptance criteria rebuilt around recall.** The prior absolute false-positive bound was satisfiable by a matcher that signals on nothing; AC1 is now a recall floor, AC2 a bounded ratio with a non-zero floor.

### Independent verification (one-shot runner, pre-`/work`)
Re-measured the plan's central empirical claim directly, since the whole design rests on it:

| design | recall vs 50 ground-truth enrolled plans |
|---|---|
| shipped regex today | 42 / 50 (plan: 42 ✓) |
| issue option 1 — delete bare `soak` | 17 / 50 regex-only (plan: ~4 post-strip) |
| chosen — structural delimiter | 42 / 50 (plan: 41 post-strip ✓) |

Ground-truth set independently reproduced at exactly 50 via
`grep -rlE 'scripts/followthroughs/[a-z0-9-]+\.sh' knowledge-base/project/plans/*.md`.
Conclusion confirmed: the option recommended by #7056 as cheapest-correct would have
cut real detections by at least 60%. The option-1 delta between measurements (17 vs ~4)
is a regex-only vs full-pipeline difference; Phase 1 re-derives and re-measures.

### Collision check (Step 0a.5)
- #7056 OPEN, #7087 OPEN — neither closed, no abort.
- Merged PR #7034 surfaced for #7056 in both the `linked:issue` and body probes. Dedupe
  puts it in both sets, so the body-probe disposition governs and the scope discriminator
  applied: `gh pr diff 7034 --name-only` intersects `ship/SKILL.md`. Resolved as a
  **citation, not a collision** — #7034 is the PR that was *blocked by* this gate (per
  #7056's own body), its only `soak` line in that file is an unrelated comment, and
  `SOAK_RE` in main still carries the bare alternative. Bug confirmed live.
- #7087: zero hits across linked-issue, body, title, and `git log --grep` probes.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Agents: `general-purpose` ×2 (learnings research, recall survey),
  `soleur:engineering:review:architecture-strategist`,
  `soleur:engineering:review:code-simplicity-reviewer`,
  `soleur:engineering:review:test-design-reviewer`,
  `soleur:engineering:review:security-sentinel`,
  `soleur:engineering:research:git-history-analyzer`,
  `soleur:product:spec-flow-analyzer`
- Gates: plan Phases 0.6 / 1.7.5 / 2.5 / 2.6 / 2.10 / 2.11; deepen-plan Phases 4.6–4.10

## Related operator decisions (this session)
- #7145 closed: operator kept the separable operator-email half of the release-alerting
  fix, with the falsified "the mirror pages nobody" rationale corrected on the record.
- #7143 and #7142 commented as operator-approved and queued to run after this PR merges.
