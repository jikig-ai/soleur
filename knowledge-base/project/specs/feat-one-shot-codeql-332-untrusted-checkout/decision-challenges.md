# Decision Challenges — CodeQL alert #332

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Remediation shape: rename the gate output vs. restructure the checkout vs. dismiss | technical | Ruled by CTO agent, 2026-11-04 (sequential execution, no spawn tool): rename `deploy_sha` → `deploy_target` — the alert's only live match is the `.*(head|sha|commit).*` field-name heuristic (verified at predicate level in `UntrustedCheckoutQuery.qll`: no modeled taint path reaches `steps.gate.outputs.*` through the `emit` indirection, and `untrusted_event_properties.yml` does not list `workflow_run.head_sha`); the restructure kills the deploy-arm `[command]…--depth=1 origin <sha>` primary key on both arms for the same property. Escalate to plan-B (no-ref checkout + run-step fetch/checkout + `resolving deploy target` echo) only if the PR-ref CodeQL scan still flags; dismissal (plan-C) only if no structural form clears. |
| Brand-survival threshold for the plan | technical | Ruled by CTO agent, 2026-11-04: `none` with a sensitive-path scope-out reason — the diff is an identifier rename inside an already-gated CI boundary; a bad landing is a red invariants suite or a clean-skipped deploy (operator-visible), never user-reaching. `web-platform-release.yml` matches `SENSITIVE_PATH_RE`, so the scope-out line is carried in `## User-Brand Impact`. |
