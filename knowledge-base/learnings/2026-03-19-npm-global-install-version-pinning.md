# Learning: npm global install version pinning in Dockerfiles

## Problem
`npm install -g <package>` without a version pin in Dockerfiles resolves to `@latest` at build time, creating non-reproducible builds and a supply-chain attack vector. Unlike local project dependencies (which have `package-lock.json`), global installs have no lockfile mechanism.

## Solution
Pin to a specific version: `npm install -g @anthropic-ai/claude-code@2.1.79`. The npm registry guarantees published versions are immutable (content-addressed SHA-512 storage), making version strings functionally equivalent to Docker image digests for immutability purposes.

## Key Insight
For global npm installs, version pinning is the only available control (no lockfile exists). npm's immutability guarantee means version pins are sufficient — no additional integrity hash is needed in the Dockerfile. The `npm unpublish` window is 72 hours for new packages; established packages cannot be re-published with different content.

## Tags
category: build-errors
module: docker
