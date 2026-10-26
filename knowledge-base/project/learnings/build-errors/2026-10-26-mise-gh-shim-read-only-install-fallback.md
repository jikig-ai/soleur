---
title: Bypass a failing mise gh shim with the installed binary in read-only shells
date: 2026-10-26
category: build-errors
module: cli-environment
---

## Problem

In a restricted shell, invoking the first `gh` found on `PATH` emitted a mise
error while trying to install `aqua:cli/cli@latest` into a read-only filesystem,
so the GitHub request never ran. The installed GitHub CLI binary was present
under mise's versioned install directory; invoking that binary succeeded after
the network permission was granted.

## Prevention

When a CLI invocation fails before contacting its target, inspect `type -a
<cli>` and the exact error. If a wrapper is attempting a forbidden install,
resolve and invoke an already-installed binary explicitly rather than
repeating the wrapper. Retry network access only through the normal approval
path.
