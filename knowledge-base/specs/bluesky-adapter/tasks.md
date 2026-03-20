# Tasks: Wire Bluesky into Community Monitor CI Workflow

## Phase 1: CI Workflow Update

- [x] 1.1 Read `.github/workflows/scheduled-community-monitor.yml`
- [x] 1.2 Add `BSKY_HANDLE: ${{ secrets.BSKY_HANDLE }}` and `BSKY_APP_PASSWORD: ${{ secrets.BSKY_APP_PASSWORD }}` to the `env:` block of the `claude-code-action` step
- [x] 1.3 Update the workflow comment header (line 2) to include Bluesky in the description
- [x] 1.4 Update the prompt Batch 1 label from "Discord + X" to "Discord + X + Bluesky"
- [x] 1.5 Add `bash $ROUTER bsky get-metrics` to the Batch 1 commands in the prompt
- [x] 1.6 Add `## Bluesky Metrics` to the optional digest sections list in the prompt

## Phase 2: Compound and Ship

- [ ] 2.1 Run compound (`skill: soleur:compound`)
- [ ] 2.2 Commit and push
- [ ] 2.3 Create PR with `Closes #852` in body

## Phase 3: Verify

- [ ] 3.1 After merge, trigger manual workflow run: `gh workflow run scheduled-community-monitor.yml`
- [ ] 3.2 Poll run until complete, verify Bluesky appears as enabled and digest includes `## Bluesky Metrics`
