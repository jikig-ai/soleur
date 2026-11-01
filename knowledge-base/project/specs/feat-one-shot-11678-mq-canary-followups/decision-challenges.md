# Decision Challenges — feat-one-shot-11678-mq-canary-followups

Headless one-shot planning run for the #11678 follow-up batch. This harness has
no Agent/Task tool, so the `soleur:plan-review` panel and any CTO rulings could
not be spawned. Technical rows carry `pending - assumed: <default>` per the
technical-ruling-delegation contract until a parent pipeline's batched
`soleur:engineering:cto` consult lands.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Ratchet drift: focused new issue vs comment on #10959 | technical | pending - assumed: focused filing per the brief's stated default — it names a distinct measured defect (live=1512 vs baseline=1510 on main HEAD, `stale-accept`) plus a concrete consequence (advisory check red on every head; only failing check on #11688; #10865's soak pauses on red "until it is repaired" and no repair issue exists); #10959 is a reveal-4 worklist that does not name this pair. Filing `Ref`s #10959 #10860 #10448 #10865 rather than duplicating. |
| `plan-review` reviewer panel not spawned (no Agent tool in this harness); self-review applied instead — does the plan need a panel re-run before `soleur:work`? | technical | pending - assumed: no panel re-run required before implementation — docs/KB-only diff, every gate ran in-process (premise validation, scope check, observability, overlap check, label verification, all prescribed probes executed at plan time); same resolution as feat-one-shot-9963. |
| Brand-survival threshold `none` | taste | assumed: none — knowledge-base documentation + issue/comment artifacts only; worst outcome is an inaccurate internal record, no user-facing artifact or data exposure. Challengeable per the template's marker. |
| ADR-270 addendum placed at EOF as `### Addendum 2026-11-01` vs inserting under `## Canary results` | technical | pending - assumed: EOF sibling — matches the file's established convention (the newest addendum, 2026-10-31, also sits at EOF at `###` level; `## Canary results` holds only the original 2026-10-04 measurement block). |
| Retitle PR #11768 `docs(arch):` and ship via `gh pr ready`/`gh pr merge --squash --auto` from the worktree cwd vs GraphQL bypass proactively | technical | pending - assumed: normal path first from the worktree cwd — docs title reads IS_FEAT=0 in ship-cmo-content-gate so the stale-cwd arms are never reached; GraphQL mutations only on denial, per the brief's documented bypass. |
