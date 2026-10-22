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

The timeout-after-candidate synthetic lifecycle test assumed child import and
receipt publication fit in 500 ms. A concurrent run violated that assumption;
a deliberate 600 ms startup delay reproduced the failure. Signal fixture
readiness after candidate flush, trigger the synthetic timeout only then, and
retain an independent real startup cap. Keep production budgets unchanged.
This proves that fixture race, not any historical operational failure.

A later wildcard discovery guessed nonexistent `.soleur/*config*.py` helpers.
List the directory's real filenames first; the existence of Config JSON records
does not imply similarly named preparation scripts exist.

## Addendum — 2026-10-22 mutation execution boundary

The new Config lifecycle suite generated mutants of a helper that calls
`process.kill()`. Primary full discovery and two review seats ran those owned
scratch-process mutants on the host. Test-design review correctly blocked that
instrument: known PIDs and scratch argv are not the required PID namespace.
Those historical green runs establish no namespace-safety coverage.

The owning work reference now explicitly covers mutants reached through default
test discovery. The suite must dispatch them through the canonical namespace
runner under `timeout -k`, prove an unmutated control, and refuse without host
fallback. A harmless namespace probe succeeded here; this does not excuse the
earlier runs. Complete corrected instrument verification before any new Config
preparation or action. Retire reaped fixture PIDs immediately and establish
cleanup ownership before readiness assertions so failed tests cannot leave
unrecorded synthetic children.

The first corrected complete discovery ran before committing its runtime test
changes. Its preparation fixture correctly refused dirty source (481 tests,
one setup error); that is not a green complete run. Commit the candidate before
running tests whose contract binds the current clean revision, then report that
exact revision and the fresh result separately.

A continuation wrapper initially required mode 0700 on the general `.soleur`
parent, but that owned directory is mode 0755. It refused before preparation or
file creation. The reviewed protocol requires mode 0700 on each action directory
and mode 0600 on private files; its ancestor traversal uses no-follow directory
descriptors. Verify those actual requirements instead of adding an unsupported
parent-mode assumption or changing a shared parent to make a wrapper pass.

A delegated proposal patch briefly created a new placeholder with a leading
space in its basename at the worktree root. The author read and removed only
that new file, then used the assigned absolute KB destination. Validate the
literal destination before applying a patch; whitespace in a patch path is
part of the filename, not indentation or a worktree selector.
