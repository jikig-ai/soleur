# Learning: CI for Notifications and Infrastructure Setup Checklist

## Problem

Built a release-announce skill that posted to Discord locally via `DISCORD_WEBHOOK_URL` env var. Three issues surfaced:

1. **Local env vars for secrets are fragile** -- every developer needs the webhook configured, and it only works when a human runs `/ship`
2. **Used GitHub Actions `vars.*` instead of `secrets.*`** -- webhook URLs are API keys; anyone with the URL can post to the channel
3. **`secrets.*` can't be evaluated in job-level `if` conditions** -- `if: secrets.X != ''` always evaluates false because secrets are masked before condition evaluation

## Solution

1. Moved Discord posting to a GitHub Actions workflow triggered on `release: published`
2. Changed `DISCORD_WEBHOOK_URL` from repository variable to repository secret
3. Moved the empty-check inside the step script instead of the job-level `if`:

```yaml
# WRONG: secrets are masked in job-level conditions
jobs:
  discord:
    if: secrets.DISCORD_WEBHOOK_URL != ''  # always false

# RIGHT: check inside the step
jobs:
  discord:
    steps:
      - env:
          DISCORD_WEBHOOK_URL: ${{ secrets.DISCORD_WEBHOOK_URL }}
        run: |
          if [ -z "$DISCORD_WEBHOOK_URL" ]; then
            echo "Secret not set, skipping"
            exit 0
          fi
          # ... post to Discord
```

## Key Insight

**Notifications belong in CI, not on developer machines.** The pattern is:
- Local skill creates the GitHub Release (needs AI for summary generation)
- CI workflow triggers on `release: published` and handles all downstream notifications
- Secrets live in GitHub Settings, not in local env vars or `.claude/settings.local.json`

This separation means: AI-powered work stays local (where Claude runs), mechanical notifications run in CI (where secrets are centrally managed).

## Prevention Strategy

Before adding any feature that uses secrets or talks to external services, ask:
1. Does this need AI/Claude? -> Local skill
2. Is this mechanical (POST to webhook, send email)? -> CI workflow
3. Does it use secrets? -> GitHub Actions secrets, never local env vars

## Company Infrastructure Setup Checklist

When a team adopts Soleur, these infrastructure pieces should be configured once and forgotten:

### Day 1: Repository Setup
- [ ] `claude plugin install soleur`
- [ ] `/soleur:sync` to populate knowledge-base from existing codebase
- [ ] `.gitignore` includes `.claude/settings.local.json`, `.env`, `*.local.*`
- [ ] Lefthook or similar pre-commit hooks installed

### Day 1: GitHub Actions Secrets
- [ ] `DISCORD_WEBHOOK_URL` -- for release announcements (Settings > Secrets > Actions)
- [ ] `ANTHROPIC_API_KEY` -- for Claude Code CI review (if using `claude.yml` workflow)

### Week 1: CI Workflows
- [ ] `ci.yml` -- tests on push to main + all PRs
- [ ] `release-announce.yml` -- Discord notification on release publish
- [ ] `claude-code-review.yml` -- automated PR review (optional)

### As You Scale
- [ ] Add coverage thresholds in `bunfig.toml` (decimal format: 0.8 not 80)
- [ ] Add `bun test` to pre-commit hooks (currently a documented gap)
- [ ] Branch protection rules: require CI pass + PR review before merge
- [ ] Secret rotation schedule for API keys

## Tags

category: implementation-patterns
module: ci, github-actions, release-announce, infrastructure
symptoms: workflow skipped, secret not available, notification not sent
