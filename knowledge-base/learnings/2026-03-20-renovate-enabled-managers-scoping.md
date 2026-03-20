# Learning: Renovate config:recommended silently enables all package managers

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
