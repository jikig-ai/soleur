---
title: "Choose the git diff endpoint that includes the working tree"
date: 2026-09-30
category: build-errors
module: git-verification
---

## Problem

`git diff --check <base>...HEAD` checks the committed tree at `HEAD`; it does not
include edits still in the working tree. A correction to a committed whitespace
issue therefore remained invisible to that command and appeared to fail again.

## Prevention

Use `git diff --check <base>` to check the working tree against a base. Use
`git diff --check <base>...HEAD` only when checking committed changes between
the merge base and `HEAD`. After staging, `git diff --cached --check` checks the
index that will be committed.
