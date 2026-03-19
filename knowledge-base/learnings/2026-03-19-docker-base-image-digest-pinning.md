# Learning: Docker base image digest pinning

## Problem
`FROM oven/bun:latest` in a Dockerfile uses a mutable tag that resolves to a different image on every pull. This creates non-reproducible builds and supply-chain risk: a compromised or broken upstream image silently affects production.

## Solution
Pin to `tag@sha256:digest` format:
```dockerfile
FROM oven/bun:1.3.11@sha256:0733e50325078969732ebe3b15ce4c4be5082f18c4ac1a0f0ca4839c2e4e42a7
```

To find the digest: `docker buildx imagetools inspect oven/bun:1.3.11` and use the top-level `Digest:` value (the manifest list digest), not a platform-specific one.

## Key Insight
Docker ignores the tag entirely when a digest is present -- `1.3.11` is purely documentary. If someone updates the tag without updating the digest, Docker silently uses the old image. This is correct behavior (immutability) but can surprise maintainers. Always update tag and digest together. Pin the manifest list digest (not platform-specific) to preserve multi-arch resolution (amd64 CI + arm64 local dev).

## Tags
category: security-issues
module: telegram-bridge
