---
name: deploy-docs
description: "This skill should be used when validating and preparing documentation for GitHub Pages deployment. It checks HTML pages, JSON validity, component counts, and provides deployment instructions. Triggers on \"deploy docs\", \"publish documentation\", \"GitHub Pages\", \"validate docs site\"."
---

# Deploy Documentation Command

Validate the documentation site and prepare it for GitHub Pages deployment.

## Step 1: Validate Documentation

Run these checks:

```bash
# Count components
echo "Agents: $(find plugins/soleur/agents -name '*.md' -not -name 'README.md' | wc -l)"
echo "Commands: $(find plugins/soleur/commands -name '*.md' -not -name 'README.md' | wc -l)"
echo "Skills: $(find plugins/soleur/skills -name 'SKILL.md' | wc -l)"

# Validate JSON
cat .claude-plugin/marketplace.json | jq . > /dev/null && echo "✓ marketplace.json valid"
cat plugins/soleur/.claude-plugin/plugin.json | jq . > /dev/null && echo "✓ plugin.json valid"

# Check all HTML files exist
for page in index agents commands skills mcp-servers changelog getting-started; do
  if [ -f "plugins/soleur/docs/pages/${page}.html" ] || [ -f "plugins/soleur/docs/${page}.html" ]; then
    echo "✓ ${page}.html exists"
  else
    echo "✗ ${page}.html MISSING"
  fi
done
```

## Step 2: Check for Uncommitted Changes

```bash
git status --porcelain plugins/soleur/docs/
```

If there are uncommitted changes, warn the user to commit first.

## Step 3: Deployment Instructions

Since GitHub Pages deployment requires a workflow file with special permissions, provide these instructions:

### First-time Setup

1. Create `.github/workflows/deploy-docs.yml` with the GitHub Pages workflow
2. Go to repository Settings > Pages
3. Set Source to "GitHub Actions"

### Deploying

After merging to `main`, the docs will auto-deploy. Or:

1. Go to Actions tab
2. Select "Deploy Documentation to GitHub Pages"
3. Click "Run workflow"

### Workflow File Content

```yaml
name: Deploy Documentation to GitHub Pages

on:
  push:
    branches: [main]
    paths:
      - 'plugins/soleur/docs/**'
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/configure-pages@v4
      - uses: actions/upload-pages-artifact@v3
        with:
          path: 'plugins/soleur/docs'
      - uses: actions/deploy-pages@v4
```

## Step 4: Report Status

Provide a summary:

```
## Deployment Readiness

✓ All HTML pages present
✓ JSON files valid
✓ Component counts match

### Next Steps
- [ ] Commit any pending changes
- [ ] Push to main branch
- [ ] Verify GitHub Pages workflow exists
- [ ] Check deployment at https://jikig-ai.github.io/soleur/
```
