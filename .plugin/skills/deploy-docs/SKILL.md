---
name: deploy-docs
description: "Validate the documentation build and prepare for GitHub Pages deployment. Runs the Eleventy build, validates output, checks component counts, and provides deployment instructions."
triggers:
- deploy docs
- deploy documentation
- eleventy build
- github pages deploy
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
test -f "_site/pages/agents.html" && echo "OK agents.html"
test -f "_site/pages/skills.html" && echo "OK skills.html"
test -f "_site/pages/changelog.html" && echo "OK changelog.html"
test -f "_site/pages/getting-started.html" && echo "OK getting-started.html"
test -f _site/404.html && echo "OK 404.html"
test -f _site/css/style.css && echo "OK style.css"
test -f _site/CNAME && echo "OK CNAME"
test -f _site/sitemap.xml && echo "OK sitemap.xml"
```

## Step 2: Verify Component Counts

Use grep to count occurrences of `component-card` in `_site/pages/agents.html` and `_site/pages/skills.html`.

Then compare with source counts:

- Agent files: count `.md` files (excluding README.md) under `plugins/soleur/agents/`
- Skill files: count `SKILL.md` files under `plugins/soleur/skills/*/`

If counts diverge, investigate missing or extra catalog entries.

## Step 3: Verify Assets

```bash
# Check CSS is not empty
test -s _site/css/style.css && echo "CSS OK" || echo "CSS EMPTY"

# Check for broken internal links (optional)
grep -r 'href="/' _site/ | grep -v 'http' | head -20
```

## Step 4: Deploy

The site deploys automatically via GitHub Actions when changes are pushed to `main`. For manual deployment:

```bash
# Push to trigger the deploy workflow
git push origin main

# Or trigger manually
gh workflow run deploy-docs.yml
```

## Verification Checklist

- [ ] All expected HTML files present in `_site/`
- [ ] Component counts match source file counts
- [ ] CSS loads correctly
- [ ] No broken internal links
- [ ] CNAME file present for custom domain
- [ ] Sitemap includes all pages
