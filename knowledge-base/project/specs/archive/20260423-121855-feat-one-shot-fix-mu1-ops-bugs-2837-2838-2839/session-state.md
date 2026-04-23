# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-mu1-ops-bugs-2837-2838-2839/knowledge-base/project/plans/2026-04-23-fix-mu1-ops-bugs-audit-runbook-plan.md
- Status: complete

### Errors
None

### Decisions
- **#2837 fix**: hash-compare inlined `HostConfig.SecurityOpt[seccomp=...]` vs on-host `/etc/docker/seccomp-profiles/soleur-bwrap.json` using `jq -cS .` canonical form + sha256sum. Detects drift in either direction. Four explicit FAIL branches (no entry / literal path / file missing / hash mismatch).
- **#2838 fix**: runbook Step 3 → `ssh <host> "bash -s" < apps/web-platform/infra/audit-bwrap-uid.sh` (stdin-pipe, no host checkout needed). Option 2 (deploy script to host) deferred to existing #2606.
- **#2839 fix**: vendor cleanup guard into `apps/web-platform/infra/mu1-cleanup-guard.mjs` exporting `assertDevCleanupEnv(env = process.env)` + `sweep()`. Double-check: `DOPPLER_CONFIG === "dev"` AND `new URL(url).hostname.split(".")[0] === "ifsccnjhymdmidffkzhl"`. Try/catch around URL parsing preserves guard's intended error shape. Switch env var `SUPABASE_URL` → `NEXT_PUBLIC_SUPABASE_URL`.
- **Test harness**: match existing repo convention (`ci-deploy.test.sh`, `orphan-reaper.test.sh`) — PASS/FAIL/TOTAL counters, MOCK_DOCKER_MODE-driven unified mock, TEST_PATH_BASE excluding `~/.local/bin`, `mktemp -d` per-case MOCK_DIR, subshell-isolated cases. Node-side guard tests invoke `node --input-type=module -e` with injected env object.
- **No new Doppler vars, no new infra resources, no migrations, no app code changes.** Project ref is hardcoded as a constant (stable infra state; a new Supabase project would need a one-line update in the same commit as the SYNTH regex).

### Components Invoked
- soleur:plan skill
- soleur:deepen-plan skill
- gh issue view (#2837, #2838, #2839)
- gh issue list --label code-review
- doppler secrets/run validation
- npx markdownlint-cli2 --fix
- git add/commit
