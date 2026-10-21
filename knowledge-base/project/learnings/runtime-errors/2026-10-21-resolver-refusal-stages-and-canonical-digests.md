---
title: Distinguish canonical manifest digests and report closed refusal stages
date: 2026-10-21
category: runtime-errors
module: Codex qualification resolver supervisor
---

## Problem

An actual-manifest review compared a raw file hash with the canonical JSON digest
returned by preparation and incorrectly treated their difference as changed
content. The stored file was canonical JSON plus a trailing newline. The mismatch
caused an unnecessary extra authorization request before the formats were compared.

The subsequent separately approved one-time command returned exit 2 and only a
generic refusal. Many supervisor startup, monitoring and cleanup paths shared that
output, so neither the refusal cause nor historical helper activity was established.
Marker/receipt absence and a clean current process snapshot did not settle history.

## Correction

Compare like digest domains. Read `prepare.py` › `canonical()` and the consuming
CLI before interpreting a hash, label canonical and stored-file hashes separately,
and verify the exact canonical-plus-newline relation without modifying the file.

The separately authorized source-only correction adds closed supervisor stage
labels, not raw errors, stdout or stderr. Synthetic fault injection covers setup,
monitoring, cleanup and finalization. Reports follow cleanup and handler restoration;
completion is withheld on late failure. This does not explain the earlier refusal
or grant another attempt. Source changes require new bindings and later approval.

Two discovery commands also guessed nonexistent specification/lint-invoker paths.
Resolve current tracked paths with `git ls-files` or `rg --files` before reading
them; an earlier path or a familiar script name is not evidence it still exists.

The first commit was blocked because the harness hook resolved its ambient bare
root's `main` rather than the shell tool's feature-worktree `workdir`. The guard's
documented `git -C <worktree>` resolution arm lets it verify the actual feature
branch. Use that explicit command context without disabling the guard.
