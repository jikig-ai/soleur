---
title: "Resolve knowledge-file paths from the tracked file list"
date: 2026-09-30
category: workflow-patterns
module: knowledge-base
---

## Problem

A read command used a guessed date in a learning filename and failed even
though the intended file existed under a different date.

## Prevention

Resolve knowledge-base examples with `rg --files <directory>` before opening
them. Do not infer a filename from a remembered date or title.
