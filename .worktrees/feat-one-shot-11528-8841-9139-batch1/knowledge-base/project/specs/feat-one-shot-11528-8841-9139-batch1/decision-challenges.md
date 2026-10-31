# Decision Challenges — feat-one-shot-11528-8841-9139-batch1

Headless one-shot planning run for issues #11528 + #8841 + #9139 (epic #10390
batch-1 per the CTO batching ruling). This harness has no Agent/Task tool, so
the `soleur:plan-review` panel, domain leaders, research fan-outs and fresh CTO
rulings could not be spawned. Technical rows carry `pending - assumed:
<default>` placeholders per the technical-ruling-delegation contract until the
parent pipeline's batched `soleur:engineering:cto` consult lands; the Ruling
column records each verdict verbatim.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Epic #10390 batching (three issues in one PR) | technical | Ruled by CTO agent, 2026-10-31: batch into 3 PRs — PR1 #11528+#8841+#9139, PR2 #8593+#8080-witness, PR3 #8595 gated on pr-merged 11653; carrier batch #8525+#8013+#8080-RestartSec+#10290 deferred to next vinngest bake/host-replace window; #8839 held for evidence pull, #9943 held for owner credential call |
| #11528 gap-1 remedy: anchored line-regex vs `exit`-on-terminator + decoy detection vs comment/HCL-aware extraction vs canonical-equality compare | technical | pending - assumed: whitespace-stripped canonical-equality compare (`WRONGVOLUME_CANON` per sibling `FAIL_CANON`), because one equality subsumes decoy-heredoc concatenation, in-heredoc comments, inline-tautology and `$$` escapes, while the other two options each leave a comment-shaped lane the structural map already measured |
| #11528 gaps 2–4 row selection (which get presence+mutation rows) | technical | pending - assumed: all — `source_variable`/`values`/`FROM {{source}}` (2), `alert_type`/`operator`/`value`/`check_period` + `count`/`for_each`/`lifecycle` negative pins (3), and `WHERE…BETWEEN` (4, subsumed by canon), per the sibling guard's `param()` set |
| #11528 family spread: same remedy across the guard family vs this file + filed remainder | technical | pending - assumed: scope to this file + file the family remainder (the issue's own second option), since canon-per-guard is a per-file design cost and a shared helper lib is a bigger refactor than this batch |
| #11528 `MUT_SKIP` CI pin: pin unset vs leave | technical | pending - assumed: pin `env -u MUT_SKIP -u <PREFIX>_GUARD_*` on the wrong-volume and key-probe run lines of `infra-validation.yml`; the other MUT_SKIP-idiom suites ride the same remainder issue |
| #8841 fix shape: report after the last step vs inside a memoized `step.run` | technical | pending - assumed: after the last step (`persist-failure` catch), matching the file's own settle convention at `:1641` and the issue's first example; a notify-step exhaustion propagates to onFailure→settle which covers that run's report |
| #9139 amendment shape: amend `connections[6]` vs a new dedicated third entry | technical | pending - assumed: amend `connections[6]` (the leg is already folded in by #11487; a third row double-models one connection) |
| Brand-survival threshold | taste | assumed: `aggregate pattern` — issue #11528 declares it verbatim ("drift-guard soundness across the Better Stack alert family"); no single-user-facing artifact or data exposure |
| `plan-review` reviewer panel + deepen fan-outs not spawned (no Agent tool in this harness); self-review + in-process gate checks applied — does the plan need a panel re-run before `soleur:work`? | technical | pending - assumed: no blocking re-run (precedent: feat-one-shot-9963 row — missing-panel residual disclosed, every gate ran in-process); `soleur:plan-review` may still run at the review stage |
| Domain-leader fan-out skipped (no Agent tool); self-assessed `engineering` only | technical | pending - assumed: engineering-only stands — no user-facing surface, no legal-doc wording change, no ops procedure change |
