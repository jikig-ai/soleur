# Runbook — Detect duplicate-solo repo connections (WEB-PLATFORM-3M)

**Type:** read-only detection (no automated remediation)
**When to run:** post-deploy of feat-repo-connect-block-offer-join (#5673), and ad-hoc
whenever `op:founder-ambiguous` pages.
**Related:** ADR-044 (Amendment 2026-06-29), `server/repo-connect-guard.ts`,
`server/resolve-founder-for-installation.ts:131`.

## What this detects

Two or more **solo** workspaces sharing the same `(github_installation_id,
normalizeRepoUrl(repo_url))`. That pair makes the non-push GitHub-webhook founder
resolver fail-closed (`>1` → `{kind:"ambiguous"}` → 404-drop + page), silently
killing PR-review / CI-failure / issue-triage drafts for the repo — production
incident **WEB-PLATFORM-3M**.

As of #5673 the connect-time guard (`repo-connect-guard.ts`) prevents a *new*
duplicate from being created. This query surfaces any **pre-existing** duplicate
pairs so the operator can re-point one workspace by **intent** (e.g. the
chatte-vs-soleur re-point of install 122213433). There is deliberately **no
automated remediation** — "keep oldest" is the wrong heuristic (the operator's real
re-point chooses by which repo each workspace *should* own, not by age), and a
wrong-keep null-out would disconnect the wrong workspace.

## The query (run read-only — Supabase MCP, or `DATABASE_URL_POOLER` read replica)

```sql
SELECT w.github_installation_id,
       lower(w.repo_url) AS repo,
       count(*),
       array_agg(w.id ORDER BY w.created_at)        AS workspace_ids,
       array_agg(w.repo_url ORDER BY w.created_at)   AS exact_repo_urls,  -- expose case variants
       array_agg(w.created_at ORDER BY w.created_at) AS created_ats
FROM workspaces w
JOIN workspace_members m
  ON m.workspace_id = w.id          -- embed FK join
 AND m.user_id = w.id               -- solo invariant (ADR-038 N2: ws.id == owner.user_id)
 AND m.role = 'owner'
WHERE w.github_installation_id IS NOT NULL
  AND w.repo_url IS NOT NULL
GROUP BY 1, 2
HAVING count(*) > 1;
```

The self-join (`m.user_id = w.id`) selects **only solo** workspaces — a team
workspace's id is a fresh uuid never equal to a member's `user_id`, so team
workspaces sharing the install are excluded (mirrors the resolver). `array_agg(…
ORDER BY created_at)` gives the operator ordered ids + per-row detail (exact
repo_url + created_at) for the keep-which decision.

## Interpreting results

- **Zero rows** → clean. No action. (Baseline at #5673 merge: clean — the live
  install 122213433 dup was already operator-resolved before this work; the two
  solo workspaces now point at different repos.)
- **A group whose `exact_repo_urls` differ only by case** (e.g. `…/Foo/Bar` vs
  `…/foo/bar`) → **NOT incident-causing** (NG4). The runtime block and the webhook
  resolver both match `repo_url` case-sensitively, and GitHub sends one canonical
  casing, so the resolver returns `found`, never `ambiguous`, for these. The query
  groups by `lower(repo_url)` (coarser → never a false negative) so it surfaces
  these benign case-variant groups; do **not** re-point them. (Mis-cased-row-
  gets-no-webhooks is a separate hardening issue, not this incident.)
- **A group with ≥2 exact-case-identical `(install, repo)` solo rows** → a genuine
  WEB-PLATFORM-3M pair. Decide by **intent** which workspace should own the repo,
  then have that workspace's owner re-point the other (connect a different repo, or
  disconnect). Do not script a bulk null-out.

## Verification (synthesized fixtures only — never prod writes)

To confirm the query shape against a known duplicate, seed a **synthesized** pair in
a non-prod DB (`cq-test-fixtures-synthesized-only`): two `workspaces` rows with
`id == owner user_id`, the same `github_installation_id`, the same normalized
`repo_url`, each with an `owner` self-row in `workspace_members`. The query must
return exactly one group with `count = 2` and both ids in `workspace_ids`. Never
seed against prod (`hr-dev-prd-distinct-supabase-projects`).
