# Decision Challenges — feat-one-shot-8593-8080-witness

Headless one-shot planning run for issue #8593 + the satisfiability-witness half
of #8080 (epic #10390 PR 2 per the standing CTO batching ruling recorded in
`specs/archive/20261031-194207-feat-one-shot-11528-8841-9139-batch1/decision-challenges.md`).
The planning subagent could not nest spawns, so `soleur:plan-review` panel,
domain leaders, research fan-outs and fresh rulings are deferred to the parent
pipeline; every `pending - assumed:` row below awaits that batched
`soleur:engineering:cto` consult.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Epic #10390 PR-2 scope (#8593 + #8080-witness in one PR) | technical | Ruled by CTO agent, 2026-10-31 (batch-1 consult, standing): batch into 3 PRs — PR1 #11528+#8841+#9139, PR2 #8593+#8080-witness, PR3 #8595 gated on pr-merged 11653 — applied verbatim |
| #8080 stale mechanism text (`inngest_host_dark_gate` "when applicable") | technical | pending - assumed: call `inngest_execute_registry_gate` only — `inngest_host_dark_gate` retired 2026-10-14 under #8316; the census suite asserts it is never called |
| Witness filing threshold N (consecutive refusals) | technical | pending - assumed: N=8 (≈2h at */15) — exceeds the gate's 5400s row-age bound so an emit-cadence artifact cannot trip it |
| Witness suppression semantics | technical | pending - assumed: `flag_armed` verdict OR armed-class `cutover_flag` ({armed,flipping,flushed,done} via the lib's `_erg_flag_class`) suppresses increment+filing — covers both in-flight and done post-cutover self-retirement; `host_serving` counts as a refusal (pre-cutover it is anomalous; post-cutover the done flag suppresses first via hb/probe flag grading when reached) |
| Enumeration bound floor for `-L` sufficiency | technical | pending - assumed: `-L N`/`--limit N` sufficient iff N ≥ 100, or `--paginate` for `gh api` — the issue's named `-L 1` + `.[].number` shape must flag; corpus convention (`--limit 100`, `--limit 200`) already satisfies it |
| `.ts` surface comment handling in the extractor | technical | pending - assumed: new `"ts"` surface treats full-line `//` comments like `#` in sh/yaml (flush+skip) — otherwise `_cron-shared.ts`/`cron-strategy-review.ts` comment prose false-positives |
| `.github/scripts/` fixture exclusion | technical | pending - assumed: glob `.github/scripts/**/*.sh` minus `*/test/` paths — test-*.sh fixtures deliberately encode probe shapes; mirrors the `.test.sh` exclusion |
| `gh api` list-vs-item discrimination | technical | pending - assumed: plural collection endpoints (`…/issues`, `…/pulls`, `…/milestones`, query-string list params) enumerate; `…/<resource>/<N>` single-resource reads stay invisible — asserted by fixture pairs |
| `cron-roadmap-review.ts` bounds (beyond the named six) | technical | pending - assumed: `gh api …/milestones` enumeration gets `--paginate`, `gh pr list --search` gets `-L` — sites enter the corpus via the asked-for glob and would red the `toEqual([])` assertion |
| `bump-inngest-bootstrap-pin.sh` `gh pr list --head` sites | technical | pending - assumed: no edit — captures carry no enumeration shape in-text and `--head <branch>` is domain-bounded like `linked:issue #N`; revisit if the census flags them |
| codeql-to-issues rewrite shape | technical | pending - assumed: existence drill `--limit 1 --jq '.[0].number // empty'` replaces `--jq 'length'` — the count only fed an existence predicate; 2026-10-06 learning: a length count is a snapshot, not a truncation proof |
| Witness label + priority | taste | pending - assumed: new label `ci/inngest-gate-witness` + `action-required` + `priority/p2-medium` — machinery fault dedupe'd per run, not a prod outage (mirrors `ci/inngest-probe-unavailable` p2) |
| Witness verdict→action classifier extracted to `scripts/inngest-gate-witness-classify.sh` | technical | pending - assumed: extraction per repo idiom ("a verdict that cannot be driven RED is not a verdict") — enables Guard 2's decision table + lib-token census |
| Brand-survival threshold | taste | assumed: `aggregate pattern` — machinery/observability diff; no single-user artifact or regulated-data exposure |
| `plan-review` reviewer panel + deepen fan-outs not spawned (no nested-spawn tool); self-review + in-process gate checks applied — does the plan need a panel re-run before `soleur:work`? | technical | pending - assumed: proceed without blocking panel re-run (batch-1 precedent: CTO ruled the same for PR 1 — `soleur:review` multi-agent pass remains mandatory pre-merge) |
| Domain-leader fan-out skipped; self-assessed `engineering` only | technical | pending - assumed: engineering-only stands — no user-facing surface, no legal-doc wording, no ops procedure change (batch-1 CTO ruled identical for PR 1) |
| #8594 overlap disposition | technical | pending - assumed: Acknowledge + partial fold-in — the plan's dedupe bound satisfies #8594 AC1; its duplicate-pair audit ACs are live-data ops the issue scoped to its own cycle; #8594 stays open, `Refs #8594` optional in body |
