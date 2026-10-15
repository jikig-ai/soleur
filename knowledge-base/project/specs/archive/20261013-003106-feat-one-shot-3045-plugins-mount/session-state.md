# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3045-plugins-mount/knowledge-base/project/plans/2026-04-29-fix-plugins-soleur-mount-empty-plan.md
- Status: complete

### Errors
None

### Decisions
- Root-cause framing: empty `/mnt/data/plugins/soleur` mount silently empty since web-platform MVP (commit `5b8e2420`). All real callers (`agent-runner.ts:542`, `cc-dispatcher.ts:424`) traverse a per-workspace symlink → empty dir → ENOENT silent-skip → zero Soleur skills/agents/MCP servers ever load in user sessions. Issue #2608 documents intended-but-never-implemented "image-baked plugin" contract.
- Reconciliation against issue body: issue claimed `cc-dispatcher.ts:387` (actually line 424); claimed `agent-runner.ts:542` is the only caller in that file (line 55-56 also declares a dead `PLUGIN_PATH` constant — plan removes it).
- Architectural pivot: Docker build context is `apps/web-platform/` per `.github/workflows/web-platform-release.yml:36`, so naive `COPY plugins/soleur` would fail. Plan adds a `vendor_plugin` opt-in input to `reusable-release.yml` that vendors `plugins/soleur` → `apps/web-platform/_plugin-vendored` before docker build. `.dockerignore` re-includes vendored tree to escape `*.md` exclusion. `.gitignore` covers local-dev parity.
- Sequencing fix: seed step uses `docker create` + `docker cp` + `docker rm` against an ephemeral container (NOT a running canary) and runs BEFORE canary `docker run` at `ci-deploy.sh:255`, so canary sees populated mount on first read. Also unblocks #3033/#3042's Layer 3 verification.
- Shell portability: cloud-init `- |` blocks run under `/bin/sh` (= `dash` on Ubuntu) — bash brace-expansion is bash-only. Plan uses `find -mindepth 1 -delete` in cloud-init and reserves bash glob for `ci-deploy.sh` (bash shebang).
- Observability cardinality: new `verifyPluginMountOnce()` fires `reportSilentFallback({ feature: "plugin-mount", op: "discovery" })` exactly once per process boot with three differentiated messages. Existing `agent-runner.ts:559` ENOENT-skip stays silent (per-user, complementary cardinality).
- Code-review overlap: #2608 (parent design, fold reference), #2955 (process-local state ADR, acknowledge with reuse hint), #2962 (memoized service-client extraction, orthogonal).
- User-Brand Impact: threshold `none` — public read-only plugin content, no auth/credentials/data/payments surface. Phase 4.6 gate passed.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Bash, Read, Write, Edit
- Phase 4.6 User-Brand Impact gate: passed
- Phase 4.5 network-outage trigger: did not match
- Institutional learnings consulted: `2026-03-20-docker-nonroot-user-with-volume-mounts.md`, `2026-02-09-plugin-staleness-audit-patterns.md`
