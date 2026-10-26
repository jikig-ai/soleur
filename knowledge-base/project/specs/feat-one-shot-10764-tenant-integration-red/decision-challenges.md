# Decision Challenges — feat-one-shot-10764-tenant-integration-red

| Item | Class | Ruling |
|---|---|---|
| Fix mechanism: plpgsql function-in-policy rewrite vs BEFORE-UPDATE trigger vs grant-narrow vs test-widening | technical | pending - assumed: plpgsql function-in-policy rewrite (preserves policy names + exact `own-row` equality semantics; plpgsql prevents planner inlining that would reproduce the seq-scan InitPlan). Evidence: live EXPLAIN ANALYZE on dev showed 17.5s InitPlan seq-scan; trigger alternative recorded in plan Alternatives. |
| Whether to also narrow `authenticated`'s table-level UPDATE grant on `public.users` | technical | pending - assumed: out of scope — PR #11180 tracks the narrowing follow-up; our fix makes the test green under either posture. |
| Whether to mutate dev by hand (REVOKE) to unblock main faster | technical | pending - assumed: no as primary fix; documented as emergency unblock only. The migration path self-heals dev via normal apply. |
| Filing follow-up issues (catalog-posture probe, dev fixture bloat) | scope | recorded in tasks.md Phase 3 — required by plan-skill deferral tracking; no operator decision needed to file tracker issues. |
