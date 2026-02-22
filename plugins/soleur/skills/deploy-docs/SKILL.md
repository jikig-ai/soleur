---
name: deploy-docs
description: "This skill should be used when validating the documentation build and preparing for GitHub Pages deployment. It runs the Eleventy build, validates output, checks component counts, and provides deployment instructions. Triggers on \"deploy docs\", \"publish documentation\", \"GitHub Pages\", \"validate docs site\"."
---

# Deploy Documentation Command

Validate the documentation build and prepare it for GitHub Pages deployment.

## Step 1: Build and Validate

```bash
# Install dependencies (if needed)
npm ci

# Run Eleventy build
npx @11ty/eleventy

# Verify build output
test -f _site/index.html && echo "OK index.html"
for page in agents skills changelog getting-started; do
  test -f "_site/pages/${page}.html" && echo "OK ${page}.html"
done
test -f _site/404.html && echo "OK 404.html"
test -f _site/css/style.css && echo "OK style.css"
test -f _site/CNAME && echo "OK CNAME"
test -f _site/sitemap.xml && echo "OK sitemap.xml"
```

## Step 2: Verify Component Counts

Use Grep to count occurrences of `component-card` in `_site/pages/agents.html` and `_site/pages/skills.html`.

Then compare with source counts using Glob:

- Agent files: count `.md` files (excluding README.md) under `plugins/soleur/agents/`
- Skill files: count `SKILL.md` files under `plugins/soleur/skills/`

Cards in the output must match source file counts exactly.

## Step 3: Check for Uncommitted Changes

```bash
git status --porcelain plugins/soleur/docs/ eleventy.config.js package.json
```

If there are uncommitted changes, warn the user to commit first.

## Step 4: Deployment

Deployment is automated via `.github/workflows/deploy-docs.yml`:

- **Trigger:** Push to `main` that changes docs, agents, skills, commands, plugin.json, or eleventy.config.js
- **Manual:** Go to Actions > "Deploy Documentation to GitHub Pages" > "Run workflow"

The workflow:
1. Checks out the repo
2. Installs Node.js 20 and npm dependencies
3. Runs `npx @11ty/eleventy` to build
4. Verifies all required files are present
5. Uploads `_site/` as a Pages artifact
6. Deploys to GitHub Pages

## Step 5: Report Status

Provide a summary:

```
## Deployment Readiness

OK All HTML pages present
OK CSS and fonts present
OK Component counts match source
OK CNAME and sitemap present

### Next Steps
- [ ] Commit any pending changes
- [ ] Push to main branch
- [ ] Verify deployment at https://soleur.ai/
```
