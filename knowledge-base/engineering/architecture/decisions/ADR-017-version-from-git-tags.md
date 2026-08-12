---
title: Version From Git Tags
status: active
date: 2026-03-27
amended_by: [ADR-182]
---

# ADR-017: Version From Git Tags

## Context

Manual version bumps caused drift between plugin.json and actual releases. Feature branches accidentally bumped versions.

## Decision

Version derived from git tags at merge time via CI (version-bump-and-release.yml). plugin.json and marketplace.json versions are frozen sentinels (0.0.0-dev). Set semver:patch/minor/major labels on PRs. CI determines version bump, creates GitHub Release with vX.Y.Z tag, and posts to Discord. Never edit version fields in feature branches.

## Consequences

Zero manual version management. Eliminates version drift. Requires semver label on every PR touching plugins/soleur/. CI is the single source of truth for versioning.

## Amendment (2026-08-12) — the frozen sentinels are removed; see ADR-182

**Superseded:** the `## Decision` sentence "plugin.json and marketplace.json versions are frozen
sentinels (0.0.0-dev)". **Still current:** everything else — version derived from git tags at merge
time, semver labels, CI as the single source of truth, and never editing version fields in feature
branches.

The sentinel was the mechanism that broke delivery. `claude plugin update` compares **version
strings**; a constant always compares equal, so the update short-circuited, reported `already at the
latest version (0.0.0-dev)`, and exited 0 having delivered nothing. Installed caches sat three
months stale while the operator was told they were current (#7471).

The fields are now **absent** rather than frozen. With no key the CLI records the plugin's commit
SHA as its version, so the string advances with every commit and the comparison detects the update.
This is a correction to *how* ADR-017 avoided drift, not a reversal of the decision: the drift
ADR-017 was written to prevent is still prevented, and versions still come from tags.

Do not read this amendment as licence to bump a version in a feature branch — there is no version
field left to bump, and adding one back reinstates the defect.

Full decision, measurements, and rollback:
[ADR-182](./ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md).
