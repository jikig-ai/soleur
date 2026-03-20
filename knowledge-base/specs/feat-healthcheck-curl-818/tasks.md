# Tasks: fix web-platform HEALTHCHECK missing curl

## Phase 1: Core Fix

- [ ] 1.1 Replace `curl -f` HEALTHCHECK with `node -e "fetch(...)"` in `apps/web-platform/Dockerfile` (lines 36-38)
- [ ] 1.2 Include `AbortSignal.timeout(4_000)` in the fetch call for deterministic timeout (4s app-level, 1s headroom before Docker's 5s kill)
- [ ] 1.3 Update the comment on line 36 from "curl is pre-installed in node:22-slim" to "uses Node.js fetch -- curl is not available in node:22-slim"

## Phase 2: Verification

- [ ] 2.1 Build the Docker image locally to verify Dockerfile syntax is valid (shell quoting of `node -e "..."` in Dockerfile CMD)
- [ ] 2.2 Confirm no other files in `apps/web-platform/` reference `curl` that would need updating
- [ ] 2.3 Verify the `node -e` one-liner runs correctly outside Docker: `node -e "fetch('http://localhost:3000/health',{signal:AbortSignal.timeout(4_000)}).then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"`
- [ ] 2.4 Confirm CI deploy health check at `.github/workflows/web-platform-release.yml:70` is unaffected (uses host curl, not container curl)
