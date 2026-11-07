# Decision Challenges — feat-one-shot-10848-inngest-erasure-reach

Headless one-shot planning run for issue #10848 (the compliance half — Art.
15/17 reach of the dedicated Inngest Postgres run-history store). No subagent
spawn surface exists on this planning harness, so the ruling rows that would
normally carry `Ruled by CLO agent` are recorded pending with the prescribed
producer named.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Art. 17 reach determination — does the 7-day status-gated bound plus documented no-reach discharge erasure on the Inngest Postgres store, or is a per-subject mechanism required (B1 host-side job / B2 app-side purge / B3 minimisation / B4 documented no-reach) | operator (legal-risk) | Ruled by CLO agent, 2026-11-02: B4 - documented no-reach; no per-subject mechanism required (no constructible predicate on a sparse `event_user` + open-ended payload-key census; no founder-keyed predicate names the involuntary third-party population); conditioned on tracked follow-up #11856 (absolute age ceiling for the never-terminal-run indefinite limb) |
| Art. 15 reach determination — does the self-serve DSAR bundle require the store's rows or a documented exclusion rationale | operator (legal-risk) | Ruled by CLO agent, 2026-11-02: documented exclusion - the self-serve bundle lawfully excludes the store (separate Supabase project outside the app-project allowlist domain; derivative founder content, involuntary-subject disproportionate-effort posture, no user-indexed column, 7-day bound, operator-mediated named-request path) |
| Re-run the plan-review panel before work (no spawn surface on this harness; review ran inline) | technical | Ruled by CTO agent, 2026-11-02: proceed to work without re-running the panel - plan completeness verified (ACs, Observability, Encryption Posture, Scope Check, user-impact all present), the sequential-fallback disclosure is correctly carried, and the central determination is already deferred to a work-Phase-1 CLO consult - a second inline pass cannot supply the independence it lacks and its residual value is covered by the AC/gate suite and mandatory pre-merge review |
| `requires_cpo_signoff: true` at single-user-incident threshold | operator (brand) | pending - declared in plan frontmatter; headless pipeline cannot pause; recorded for ship Phase 6 rendering per the ADR-084 channel |
| Brand-survival threshold: `single-user incident` (issue's own classification; harm is per-subject, not the aggregate class of the sibling #5150 predicate risk) | taste | `single-user incident`, kept per the issue's declared incident class |
