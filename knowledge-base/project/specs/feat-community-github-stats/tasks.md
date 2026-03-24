# Tasks: Add GitHub Stars, Forks, and New Stargazers to Daily Community Report

## Phase 1: Core Implementation

- [ ] 1.1 Add `cmd_repo_stats` function to `plugins/soleur/skills/community/scripts/github-community.sh`
  - [ ] 1.1.1 Implement repo metadata fetch via `gh api repos/{owner}/{repo}`
  - [ ] 1.1.2 Implement stargazers fetch via `gh api repos/{owner}/{repo}/stargazers` with `Accept: application/vnd.github.star+json` header and `--paginate`
  - [ ] 1.1.3 Filter new stargazers by `since` date (reuse `date_n_days_ago` helper)
  - [ ] 1.1.4 Apply `check_rate_limit` to both API responses
  - [ ] 1.1.5 Combine into structured JSON output with jq
- [ ] 1.2 Register `repo-stats` in the `main()` case statement of `github-community.sh`
- [ ] 1.3 Update the usage text in `github-community.sh` to include `repo-stats [days]`

## Phase 2: Workflow Integration

- [ ] 2.1 Update `.github/workflows/scheduled-community-monitor.yml` prompt Batch 2 to include `bash $ROUTER github repo-stats 1`
- [ ] 2.2 Update Step 4 digest format instructions to include repository stats table and new stargazers list in the `## GitHub Activity` section

## Phase 3: Documentation

- [ ] 3.1 Update `plugins/soleur/skills/community/SKILL.md` github-community.sh description to include `repo-stats`

## Phase 4: Validation

- [ ] 4.1 Run `github-community.sh repo-stats` locally and verify JSON output
- [ ] 4.2 Run `github-community.sh repo-stats 1` and verify new_stargazers filtering
- [ ] 4.3 Verify `github-community.sh` with no args shows updated usage text
