---
title: 'Renovate config:recommended silently enables all package managers'
date: 2026-03-20
category: engineering
tags: [dependency-management, ci-cd]
---

# Learning: Renovate config:recommended silently enables all package managers

> **SUPERSEDED IN PART, 2026-08-05 (#7282).** This document states that `renovate.json5`
> enables the `dockerfile` manager and extends `default:automergeDigest` + `platformAutomerge`,
> and its Prevention section instructs the reader to *"check `renovate.json5` for whether a bot
> mutates it."* **Renovate has never run against this repository** — zero Renovate-authored PRs
> in its entire history, no Dependency Dashboard issue — so the config was inert and #7282
> deleted it. The reasoning below is sound and worth keeping; only the mechanism is wrong, and
> it inverts rather than disappears: with nothing moving the leader, the risk is not a fast
> automerged bot bump outrunning its followers, it is **the whole set rotting in agreement**,
> which strengthens the case for leader-anchoring. When applying the Prevention step, ask "what
> moves this leader, if anything?" rather than grepping a file that no longer exists.
> See the ADR-096 "Pin freshness" amendment.

## Problem

Renovate's `config:recommended` preset (formerly `config:base`) enables every built-in manager by default -- npm, pip, Terraform, Docker, GitHub Actions, Maven, Cargo, and dozens more. In a monorepo that intentionally pins only Docker digests and GitHub Actions SHAs, this default floods the repository with unwanted PRs for `package.json` dependencies, Terraform providers, and any other ecosystem Renovate detects. The Renovate docs do not prominently warn that adopting `config:recommended` opts you into ALL managers.

## Solution

Use `enabledManagers` to explicitly scope Renovate to only the dependency categories you want automated:

```json5
enabledManagers: ["dockerfile", "github-actions", "custom.regex"],
```

This ensures Renovate only creates PRs for Dockerfiles, GitHub Actions workflows, and any custom regex managers you define -- ignoring `package.json`, `*.tf`, `requirements.txt`, and everything else.

Without `enabledManagers`, the only alternative is `ignoreDeps` / `packageRules` with `enabled: false` for every unwanted package -- which is brittle and breaks silently when new dependencies are added.

## Key Insight

Renovate presets are additive and greedy by default. `config:recommended` is not "recommended defaults for what you already manage" -- it is "manage everything Renovate can detect." When adopting Renovate for a specific purpose (e.g., digest rotation only), always pair `config:recommended` with `enabledManagers` to prevent scope creep. This is the Renovate equivalent of a firewall default-deny policy: explicitly allow what you want, block everything else.

## Tags

category: dependency-management
module: ci-cd
