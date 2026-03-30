# Tasks: chore: automated rule audit CI

## Phase 1: Script Infrastructure

- [ ] 1.1 Create `scripts/rule-audit/` directory
- [ ] 1.2 Create `scripts/rule-audit/count-rules.sh`
  - [ ] 1.2.1 Add shebang, `set -euo pipefail`, SCRIPT_DIR/REPO_ROOT pattern
  - [ ] 1.2.2 Verify AGENTS.md and constitution.md exist, exit 1 if not
  - [ ] 1.2.3 Count `^-` lines in AGENTS.md (under rule section headings only)
  - [ ] 1.2.4 Count `^-` lines in constitution.md (all lines)
  - [ ] 1.2.5 Output JSON: `{"total": N, "agents_md": N, "constitution_md": N, "threshold": 300, "over": bool}`
  - [ ] 1.2.6 Make executable (`chmod +x`)
  - [ ] 1.2.7 Test locally: `bash scripts/rule-audit/count-rules.sh | jq .`
- [ ] 1.3 Create `scripts/rule-audit/detect-duplication.sh`
  - [ ] 1.3.1 Extract `[hook-enforced: ...]` annotated rules from AGENTS.md
  - [ ] 1.3.2 Extract `[hook-enforced: ...]` annotated rules from constitution.md
  - [ ] 1.3.3 Verify referenced hook scripts exist in `.claude/hooks/`
  - [ ] 1.3.4 Extract key phrases (3+ words) from each always-loaded rule
  - [ ] 1.3.5 Search `plugins/soleur/agents/**/*.md` descriptions for matching phrases
  - [ ] 1.3.6 Search `plugins/soleur/skills/*/SKILL.md` for matching phrases
  - [ ] 1.3.7 Output JSON array of findings with source/target tier, file, line, phrase, recommendation
  - [ ] 1.3.8 Make executable, test locally
- [ ] 1.4 Create `scripts/rule-audit/generate-report.sh`
  - [ ] 1.4.1 Accept count JSON and findings JSON as arguments (file paths)
  - [ ] 1.4.2 Generate issue body Markdown: budget stats table, findings table, tier model reference
  - [ ] 1.4.3 If duplicates found: create `chore/rule-audit-YYYY-MM-DD` branch
  - [ ] 1.4.4 Apply proposed migrations (move rules between files, add annotations)
  - [ ] 1.4.5 Add `[CANDIDATE FOR DELETION]` comments for obsolete rules
  - [ ] 1.4.6 Output issue body to stdout, PR branch name to stderr
  - [ ] 1.4.7 Make executable, test locally
- [ ] 1.5 Create `scripts/rule-audit/fingerprint.sh`
  - [ ] 1.5.1 Accept findings JSON file path as argument
  - [ ] 1.5.2 Sort findings, compute SHA256, take first 12 chars
  - [ ] 1.5.3 Search open issues for label `rule-audit:<fingerprint>`
  - [ ] 1.5.4 Output "skip" or "create" to stdout, fingerprint to stderr
  - [ ] 1.5.5 Make executable, test locally

## Phase 2: GitHub Actions Workflow

- [ ] 2.1 Create `.github/workflows/rule-audit.yml`
  - [ ] 2.1.1 Add schedule trigger: `cron: '0 9 1,15 * *'`
  - [ ] 2.1.2 Add `workflow_dispatch` trigger
  - [ ] 2.1.3 Set concurrency group `scheduled-rule-audit` with `cancel-in-progress: false`
  - [ ] 2.1.4 Set permissions: `contents: write`, `issues: write`, `pull-requests: write`
  - [ ] 2.1.5 Add checkout step with pinned action SHA
  - [ ] 2.1.6 Add step: run `count-rules.sh`, save JSON to file
  - [ ] 2.1.7 Add step: run `detect-duplication.sh`, save findings to file
  - [ ] 2.1.8 Add step: run `fingerprint.sh`, capture status
  - [ ] 2.1.9 Add conditional step: if "create", run `generate-report.sh`
  - [ ] 2.1.10 Add conditional step: create label `rule-audit:<fingerprint>` via `gh label create`
  - [ ] 2.1.11 Add conditional step: create issue via `gh issue create` with `--milestone "Post-MVP / Later"` and fingerprint label
  - [ ] 2.1.12 Add conditional step: if PR branch exists, create PR via `gh pr create`
  - [ ] 2.1.13 Add skip annotation step if fingerprint matches
  - [ ] 2.1.14 Ensure no heredoc indentation in `run:` blocks
  - [ ] 2.1.15 Add security comment header (no untrusted input)

## Phase 3: Verification

- [ ] 3.1 Run `npx markdownlint-cli2 --fix` on any changed `.md` files
- [ ] 3.2 Commit and push all scripts and workflow
- [ ] 3.3 After merge: trigger manual run via `gh workflow run rule-audit.yml`
- [ ] 3.4 Poll run status until complete, investigate any failures
- [ ] 3.5 Verify issue and/or PR were created correctly
- [ ] 3.6 Verify fingerprint label was applied
- [ ] 3.7 Re-trigger workflow manually to verify idempotency (should skip)
