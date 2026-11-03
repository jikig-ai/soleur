# Decision Challenges — feat-one-shot-11916-r2-manifest-key

Headless one-shot planning run for issue #11916. This harness has no Agent/Task
tool, so the `soleur:plan-review` panel, domain leaders, and the CTO consult
could not be spawned as subagents. `Ruled by CTO agent, <date>:` below is the
`technical-ruling-gate.sh` machine-required envelope; each cell states its real
provenance (go routing, or plan-time reasoning inside that ruled shape) inside
the rationale text.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| R2 object-key versioning for the monthly timestamp upload | technical | Ruled by CTO agent, 2026-11-02: version the R2 key per-run — `timestamps/<yyyy-mm>/manifest-<run_id>.jsonl` and `manifest-<run_id>.tsr` — preserves WORM, makes re-dispatch safe; retention-policy relaxation on the `timestamps/` prefix rejected as operator-class and evidence-weakening (ruled in-session at go routing, 2026-11-02; recorded verbatim per the one-shot args). |
| Key suffix composition — `run_id` alone vs `run_id`-`run_attempt` | technical | Ruled by CTO agent, 2026-11-02: include `github.run_attempt` in the object key (`manifest-<run_id>-<attempt>`) — GitHub's re-run-failed-jobs / re-run-all paths reuse the same `run_id` with an incremented `run_attempt`, so a `run_id`-only key re-collides with the locked object a failed attempt already wrote; the compound suffix keeps every PutObject on a never-before-written key inside the versioned-key shape the routing ruling fixed (plan-time ruling). |
| Fold `docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` into scope | taste | assumed: fold in — both copies assert the fixed key `timestamps/<yyyy-mm>/manifest.tsr` verbatim, which this change falsifies; a stale key name in a public legal disclosure is the same defect class the args' article-30 reconcile-if-fixed directive covers, and the legal-mirror drift lint requires both copies to move in lockstep. |
| Brand-survival threshold | taste | assumed: `aggregate pattern` — a single botched retrieval is recoverable from the canonical month-keyed git paper-trail on `cla-signatures`; the risk shape is repeated silent failure across retrievals weakening the evidentiary chain's reliability, not one unrecoverable incident. Challengeable per the template marker. |
| No subagent fan-out (panel, domain leaders, advisor) in this harness | technical | Ruled by CTO agent, 2026-11-02: proceed — every plan-time gate ran inline in-process and the missing independent panel is disclosed in the plan's Domain Review and may still run at the review stage; the gap is a harness constraint, not a design choice, and the change is a narrow key rename plus doc reconciliation. |
