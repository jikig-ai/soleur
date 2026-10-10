# Learning: verify a brief's "docs-only skips release/deploy" claim against the workflow path filter before repeating it in the PR body

**Date:** 2026-10-09 · **Source:** PR #9887 (deploy-status-debugging bwrap rows) · **Class:** workflow/premise

## Problem

The task brief asserted the docs-only change "ships with release/deploy skipped by path filter". The premise was false: `plugins/soleur/skills/**` sits inside `web-platform-release.yml`'s `on.push.paths` (excludes only `docs/`+`test/`), and `reusable-release.yml`'s change detection sees it too — merging the PR fires a release+deploy arm. Had the claim been repeated into the PR body, it would have mis-set operator expectations and the postmerge monitor.

## Solution

Two-minute verification, done at plan time: read the literal `on.push.paths`/`path_filter` blocks of the workflows the merge will trigger and compare against the diff's file list — never accept "docs-only" as self-evident. The path-filter boundary in this repo is narrower than intuition suggests (`plugins/soleur/docs/**` and `plugins/soleur/test/**` skip; `plugins/soleur/skills/**` does NOT).

## Signals to reuse

- Any brief asserting "skipped by path filter" — verify with `gh workflow view` / grep of the `paths:` block before writing the claim in a PR body or plan.
- A path-filter list also carries overclaims of the inverse shape: `on.push.paths` "contains exactly <one path>" read as sole-trigger — the real `apply-deploy-pipeline-fix.yml` filter lists 31 entries.
