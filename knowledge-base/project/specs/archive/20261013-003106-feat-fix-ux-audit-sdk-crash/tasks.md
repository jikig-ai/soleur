# Tasks: fix scheduled-ux-audit.yml failures

## Phase 1: Fix workflow file

- [ ] 1.1 Remove `push` trigger block from `.github/workflows/scheduled-ux-audit.yml` (lines 28-31)
- [ ] 1.2 Update workflow header comment to document push trigger removal with rationale
- [ ] 1.3 Replace `--only-secrets` flag with grep filter in "Inject Doppler secrets (prd)" step (lines 92-93)
  - [ ] 1.3.1 Add `allowed` variable with pipe-separated secret names
  - [ ] 1.3.2 Pipe `doppler secrets download` output through `grep -E "^($allowed)="`

## Phase 2: Verify

- [ ] 2.1 Push branch to remote
- [ ] 2.2 Trigger manual workflow run via `gh workflow run scheduled-ux-audit.yml`
- [ ] 2.3 Verify Doppler step has no `Error: unknown flag` output
- [ ] 2.4 Verify `claude-code-action` step runs without `Unsupported event type` error
- [ ] 2.5 Confirm workflow completes past both fixed steps
