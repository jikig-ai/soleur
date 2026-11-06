# Decision Challenges — feat-one-shot-11678-mq-canary-followups

Headless one-shot planning run for the #11678 follow-up batch. The planning
subagent had no Agent/Task tool, so the `soleur:plan-review` panel and CTO
rulings could not be spawned inside it. The parent pipeline landed the batched
`soleur:engineering:cto` consult on 2026-11-01 (all four technical rows below).

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Ratchet drift: focused new issue vs comment on #10959 | technical | Ruled by CTO agent, 2026-11-01: Confirmed — file the focused new issue - #10959 is a scoped S4-PR4b worklist that does not name the measured stale-accept main-drift pair (live=1512 vs baseline=1510), while #10865's soak pauses on red "until it is repaired" and no repair issue exists, so a distinct tracked filing with the measurement, consequence, fix size, and Ref lines to #10959/#10860/#10448/#10865 is the right vehicle. |
| `plan-review` reviewer panel not spawned (no Agent tool in this harness); self-review applied instead — does the plan need a panel re-run before `soleur:work`? | technical | Ruled by CTO agent, 2026-11-01: Confirmed — no panel re-run required before implementation - the diff is knowledge-base-only, every deepen-plan gate ran in-process, and the identical row in specs/feat-one-shot-9963-syslog-systemd-journald-path/decision-challenges.md was previously ruled the same way; the exemption dissolves if the work phase grows the diff beyond `knowledge-base/`. |
| Brand-survival threshold `none` | taste | assumed: none — knowledge-base documentation + issue/comment artifacts only; worst outcome is an inaccurate internal record, no user-facing artifact or data exposure. Challengeable per the template's marker. |
| ADR-270 addendum placed at EOF as `### Addendum 2026-11-01` vs inserting under `## Canary results` | technical | Ruled by CTO agent, 2026-11-01: Confirmed — append `### Addendum 2026-11-01` at EOF - the file's convention is `###`-level addendum siblings at end-of-file (the newest, 2026-10-31 #11678, sits at :982 as the last heading), while `## Canary results` (:604) holds only the original 2026-10-04 block; re-check the merge base before commit to bound the hot-file conflict surface. |
| Retitle PR #11768 `docs(arch):` and ship via `gh pr ready`/`gh pr merge --squash --auto` from the worktree cwd vs GraphQL bypass proactively | technical | Ruled by CTO agent, 2026-11-01: Confirmed — retitle `docs(arch):` and use normal `gh pr ready` / `gh pr merge --squash --auto` from the worktree cwd - ship-cmo-content-gate.sh sets IS_FEAT=1 only on a `^feat` title and exits 0 at IS_FEAT=0 before the cwd-dependent arms carrying the #11682 defect, so the deny paths are unreachable; the GraphQL pair stays the documented fallback on an actual denial, and any such denial is itself new evidence logged on #11682 before bypassing. |
