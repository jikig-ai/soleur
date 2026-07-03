# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-03-fix-git-data-userdata-32kb-gzip-plan.md
- Status: complete

### Errors
None. All planning gates passed (premise validation, User-Brand Impact, Observability, PAT, UI-wireframe halts).

### Decisions
- Mechanism: gzip-first via Terraform `base64gzip()` — measured ~21,929 B vs 32,768 cap (~10 KB headroom). R2/GHCR HTTPS-fetch fallback not needed; contingency-only. Zero content edits to template/scripts; only the `user_data` expression changes.
- Decode path code-confirmed via cloud-init `DataSourceHetzner.maybe_b64decode` — base64 is mandatory, `base64gzip()` is the intended path (cloud-init >=20.3; Ubuntu 24.04).
- Size-guard test must gzip REAL script content, not `"x".repeat(N)` placeholder (x-runs compress ~1000:1, non-discriminating). Added discrimination sanity-check.
- Dropped throwaway-host boot smoke-test (source-confirmed decode); #5887 fail-closed provisioning readiness is the empirical gate. Corrected AC3 (refs known-after-apply).
- Apply-path inert on live infra: `hcloud_server.git_data` not in auto-apply `-target` allow-list; provisioning stays gated behind #5887. ADR-080 amended (not new ADR); no C4 change.

### Components Invoked
- Skill: soleur:plan (#5927)
- Skill: soleur:deepen-plan
- Agents: framework-docs-researcher, architecture-strategist, code-simplicity-reviewer, security-sentinel
- Tools: WebSearch, ToolSearch, node/zlib measurement, gh/git/grep
