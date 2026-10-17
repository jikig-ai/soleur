# Session State — one-shot #10379

- **Issue**: #10379 OPEN — `preflight-worm-cascade-contradiction.sh` scans only `confrelid=public.users`; misses table-to-table WORM FK chains (how the #10254 wedge shipped undetected).
- **Branch/worktree**: `feat-one-shot-10379-preflight-transitive-fk` @ `.worktrees/feat-one-shot-10379-preflight-transitive-fk`. Draft PR #10417.
- **Tally**: `feat-one-shot-10379-preflight-transitive-fk-1a22fe` init'd; agent_rounds gate before each spawn batch.
- **Audit comment** (issuecomment-6193176714): no live wedge today; dormant anchors = `dsar_export_audit_pii.job_id → dsar_export_jobs` (SET NULL, mig-160 carve-out is user_id-scoped only) + `action_sends.grant_id → scope_grants` (bare REFERENCES/NO ACTION). Safe-shape refs: email_triage_items/template_authorizations non-user FKs are RESTRICT.
- **Design tension for planner**: stricter gate will flag the two dormant anchors red on main → needs a reviewed allowlist/suppression mechanism OR the anchors get fixed. Deliberate option.
- **Prior arc closed**: #10254/mig162 merged (PR #10385, v3.339.6), verify 8/8 bad=0 on dev.
