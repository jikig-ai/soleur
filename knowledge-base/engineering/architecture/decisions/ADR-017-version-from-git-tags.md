---
adr: ADR-017
title: Version From Git Tags
status: active
date: 2026-03-27
---

# ADR-017: Version From Git Tags

## Context

Manual version bumps caused drift between plugin.json and actual releases. Feature branches accidentally bumped versions.

## Decision

Version derived from git tags at merge time via CI (version-bump-and-release.yml). plugin.json and marketplace.json versions are frozen sentinels (0.0.0-dev). Set semver:patch/minor/major labels on PRs. CI determines version bump, creates GitHub Release with vX.Y.Z tag, and posts to Discord. Never edit version fields in feature branches.

## Consequences

Zero manual version management. Eliminates version drift. Requires semver label on every PR touching plugins/soleur/. CI is the single source of truth for versioning.
