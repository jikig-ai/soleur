---
date: 2026-10-26
category: integration-issues
---

# RLS policy self-subqueries seq-scan to 57014; SECURITY INVOKER policy helpers inherit caller RLS and re-hang

Two stacked traps, one incident (#10764):

1. **A correlated-looking self-subquery in a policy is actually an uncorrelated InitPlan that seq-scans the whole table.** `<col> IS NOT DISTINCT FROM (SELECT <col> FROM t WHERE id = auth.uid())` inside a RESTRICTIVE policy plans as an InitPlan over `Seq Scan` (17.5s on dev's ~295k-row users; prd's ~18 rows masked it) — a denied write returns 57014 (statement_timeout) instead of 42501 the moment a table-level grant exists. Fix: `plpgsql STABLE SECURITY DEFINER` function doing a parameterized PK lookup — plpgsql bodies never inline; LANGUAGE sql would inline right back into the InitPlan.

2. **INVOKER is not enough.** A `SECURITY INVOKER` helper's inner `SELECT ... FROM public.users` runs under the CALLER's SELECT RLS — which here included `users_jti_not_denied` (`is_jti_denied_from_jwt()` per row), re-hanging the inner query past the timeout for fresh-caller JWTs (measured: fresh-caller REST PATCH 57014/8073ms). `SECURITY DEFINER` bypasses caller RLS on the inner read; it is safe because the function is `auth.uid()`-pinned to the caller's own row. Pin `SET search_path = public, pg_temp`, qualify `public.<table>`, REVOKE the full API-role set (Supabase default privileges grant EXECUTE to anon/authenticated/service_role explicitly — `FROM PUBLIC` alone leaves them; a verify-file proacl check caught this), GRANT EXECUTE to `authenticated` only.

Side observation worth institutionalizing: `check-red-on-main.sh` filed the issue at first red; the red returned when a sibling PR's `ALLOW_UNMERGED_DEV_APPLY` run applied its verbatim prd-grant snapshot to shared dev — shared-dev catalog drift, not a code regression (cf. learnings 2026-06-15, 2026-05-21, 2026-07-03).
