---
title: Private document generation pattern
category: integration-issues
tags: [gdpr, compliance, gitignore, private-documents, shell-script]
module: legal
severity: low
date: 2026-02-21
---

# Learning: Private document generation pattern

## Problem

GDPR Article 30 requires maintaining a processing register that must NOT be in a public repository but must be reproducible on regulatory request. The template content belongs in the repo (for versioning and review), but the filled output does not.

## Solution

Separate the template (versioned, public) from the generated output (gitignored, private):

1. Template lives in `knowledge-base/specs/archive/` -- versioned, reviewable
2. Shell script in `scripts/` reads template, fills placeholders with `sed`, writes to repo root
3. `.gitignore` entry prevents accidental commits of the output
4. Script prints private storage instructions after generation

```bash
# Pattern: versioned template + gitignored output
sed "s/\[DATE\]/$TODAY/g" "$TEMPLATE" > "$OUTPUT"
```

## Key Insight

When compliance requires a private document derived from a public template, version the tooling (script + template) but gitignore the output. The script itself serves as documentation of how to reproduce the document -- no separate README needed.

## Tags

category: integration-issues
module: legal
