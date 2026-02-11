---
status: pending
priority: p3
issue_id: "010"
tags: [code-review, security, infrastructure]
dependencies: []
---

# Verify Dockerfile install script integrity

## Problem Statement

`curl -fsSL https://claude.ai/install.sh | sh` in Dockerfile has no checksum verification.

## Findings

- **security-sentinel**: MEDIUM -- classic curl-pipe-shell antipattern

## Proposed Solutions

Pin to specific version, verify SHA-256 checksum, or use official package.
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] Install script downloaded and checksum verified before execution

## Work Log
- 2026-02-11: Identified during /soleur:review
