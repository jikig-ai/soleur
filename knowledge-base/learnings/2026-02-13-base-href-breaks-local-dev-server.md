---
title: "base href for GitHub Pages breaks local dev server testing"
category: implementation-patterns
tags: [github-pages, base-href, local-testing, static-site, http-server]
module: docs
symptom: "CSS and links broken when serving GitHub Pages site locally with python http.server"
root_cause: "base href='/soleur/' makes browser resolve all relative URLs under /soleur/ path, but local server serves from root /"
---

# base href Breaks Local Dev Server

## Problem

GitHub project pages are served at `https://org.github.io/repo/`, so `<base href="/soleur/">` is needed for correct path resolution. But when testing locally with `python3 -m http.server 8765` in the `docs/` directory, the browser resolves `css/style.css` to `/soleur/css/style.css` which returns 404.

The first screenshot showed a completely unstyled page -- all CSS, links, and navigation were broken.

## Solution

Create a directory structure that matches the GitHub Pages path:

```bash
mkdir -p /tmp/soleur-docs-test/soleur
cp -r plugins/soleur/docs/* /tmp/soleur-docs-test/soleur/
cd /tmp/soleur-docs-test
python3 -m http.server 8766
# Access at http://localhost:8766/soleur/index.html
```

This mirrors the GitHub Pages URL structure (`/soleur/`) so the `<base href="/soleur/">` resolves correctly.

## Prevention

When adding `<base href>` to any static site:
1. Document the local testing setup in a README or comment
2. Consider a Makefile target: `make serve` that handles the path setup
3. Alternative: use a conditional base href that detects localhost vs production (adds JS complexity though)

## Key Insight

The `<base href>` tag affects ALL relative URLs in the document -- CSS, JS, images, and navigation links. A mismatch between the base href path and the server's directory structure will break everything silently.
