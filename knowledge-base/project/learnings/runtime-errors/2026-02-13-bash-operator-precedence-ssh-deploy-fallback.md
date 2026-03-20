---
title: "SSH Operator Precedence in Bash Deploy Scripts"
category: runtime-errors
tags: [bash, ssh, operator-precedence, docker, deployment, set-euo-pipefail]
module: deploy-skill
symptom: "Docker container starts with stale image after failed pull because || true catches the pull failure"
root_cause: "Bash && and || have equal precedence (left-to-right), so command1 && command2 || true && command3 evaluates as (command1 && command2 || true) && command3, causing || true to suppress pull failure and proceed to docker run with stale/missing image"
date_discovered: "2026-02-13"
severity: critical
---

# Learning: SSH Operator Precedence in Bash Deploy Scripts

## Problem

A deploy script that SSHs into a remote host and chains Docker commands with `&&` and `||` operators was silently continuing execution when critical steps failed. When `docker pull` failed, the `|| true` fallback on a later command caught the failure, allowing `docker run` to start a container with a stale or missing image.

## Investigation

Three independent review agents (pattern-recognition-specialist, security-sentinel, code-simplicity-reviewer) all flagged the same bug in `deploy.sh`. The convergence across all reviewers confirmed it as a critical issue rather than a stylistic concern.

Manual execution tracing revealed the evaluation order:

```text
docker pull (fails, exit 1)
  && docker stop (SKIPPED by short-circuit)
  || true (CATCHES the failure, exit 0)
  && docker rm || true (runs, exit 0)
  && docker run (RUNS with stale image!)
```

## Root Cause

Bash operators `&&` and `||` have **equal precedence** and evaluate **left-to-right**. Without explicit grouping, the statement:

```bash
docker pull $IMAGE && docker stop $CONTAINER || true && docker rm $CONTAINER || true && docker run ...
```

evaluates as a flat left-to-right chain. The `|| true` intended to catch only `docker stop` failures also catches `docker pull` failures because there is no grouping boundary.

## Solution

Use explicit grouping with `{ ...; }` to scope the `|| true` fallback to individual commands:

```bash
# WRONG - || true catches pull failure
ssh "$HOST" "docker pull $IMAGE:$TAG \
  && docker stop $CONTAINER 2>/dev/null || true \
  && docker rm $CONTAINER 2>/dev/null || true \
  && docker run -d --name $CONTAINER --restart unless-stopped $IMAGE:$TAG"

# CORRECT - { ...; } isolates || true to stop/rm only
ssh "$HOST" "docker pull $IMAGE:$TAG \
  && { docker stop $CONTAINER 2>/dev/null || true; } \
  && { docker rm $CONTAINER 2>/dev/null || true; } \
  && docker run -d --name $CONTAINER --restart unless-stopped $IMAGE:$TAG"
```

With grouping:
- If `docker pull` fails, the first `&&` short-circuits and the entire chain stops
- `|| true` only applies within its `{ ...; }` group (stop/rm may legitimately have no container)
- `docker run` only executes if all prior critical steps succeeded

## Key Insight

When chaining bash commands with `&&` and `||`, always use `{ ...; }` grouping around any `|| true` fallback. Without it, the fallback silently absorbs failures from earlier commands in the chain. This is especially dangerous in SSH commands where `set -e` does not apply to the remote shell.

## Tags

category: runtime-errors
module: deploy-skill
