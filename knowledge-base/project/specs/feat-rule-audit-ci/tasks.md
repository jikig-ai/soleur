# Tasks: chore: automated rule audit CI

## Phase 1: Script

- [x] 1.1 Create `scripts/rule-audit.sh`
  - [x] 1.1.1 Add shebang `#!/usr/bin/env bash`, `set -euo pipefail`
  - [x] 1.1.2 Add `SCRIPT_DIR` / `REPO_ROOT` pattern (match `scripts/weekly-analytics.sh`)
  - [x] 1.1.3 Verify `AGENTS.md` and `knowledge-base/project/constitution.md` exist, exit 1 if not
  - [x] 1.1.4 Count rules: `grep -c '^- ' AGENTS.md` and `grep -c '^- ' constitution.md`
  - [x] 1.1.5 Extract `[hook-enforced: ...]` annotated rules from AGENTS.md with line numbers
  - [x] 1.1.6 Extract `[hook-enforced: ...]` annotated rules from constitution.md with line numbers
  - [x] 1.1.7 For each annotation, verify referenced hook script exists in `.claude/hooks/`
  - [x] 1.1.8 Identify AGENTS.md hook-enforced rules as migration candidates (could move to constitution.md)
  - [x] 1.1.9 Build issue body Markdown: budget stats, migration candidates table, broken references, tier model
  - [x] 1.1.10 Write issue body to temp file (avoid heredoc indentation issues)
  - [x] 1.1.11 Title-based dedup: `gh issue list --state open --search "in:title \"rule audit findings\""`
  - [x] 1.1.12 If open issue exists: `gh issue comment` with updated findings
  - [x] 1.1.13 If no open issue: `gh issue create --milestone "Post-MVP / Later"` with body from temp file
  - [x] 1.1.14 Retry `gh` once after 60s on failure
  - [x] 1.1.15 Make executable (`chmod +x`)
  - [x] 1.1.16 Test locally: `GH_TOKEN=$(gh auth token) GH_REPO=jikig-ai/soleur bash scripts/rule-audit.sh`

## Phase 2: Workflow

- [x] 2.1 Create `.github/workflows/rule-audit.yml`
  - [x] 2.1.1 Add `schedule: cron: '0 9 1,15 * *'` and `workflow_dispatch`
  - [x] 2.1.2 Set `concurrency: group: scheduled-rule-audit, cancel-in-progress: false`
  - [x] 2.1.3 Set `permissions: issues: write`
  - [x] 2.1.4 Add job with `runs-on: ubuntu-latest`, `timeout-minutes: 5`
  - [x] 2.1.5 Add checkout step: `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1`
  - [x] 2.1.6 Add run step: `bash scripts/rule-audit.sh` with env `GH_TOKEN`, `GH_REPO`
  - [x] 2.1.7 Add Discord failure notification step with `if: failure()`
  - [x] 2.1.8 Add security comment header (no untrusted input)
  - [x] 2.1.9 Verify no heredoc indentation in `run:` blocks

## Phase 3: Verification

- [x] 3.1 Run `npx markdownlint-cli2 --fix` on any changed `.md` files
- [ ] 3.2 Commit and push script and workflow
- [ ] 3.3 After merge: trigger `gh workflow run rule-audit.yml`
- [ ] 3.4 Poll run status until complete, investigate failures
- [ ] 3.5 Verify issue was created with correct body, milestone, and findings
- [ ] 3.6 Re-trigger workflow to verify dedup (should comment, not create new issue)
