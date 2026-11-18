---
title: "Use gh's advertised JSON field names"
date: 2026-11-18
category: workflow-issues
tags: [github-cli, verification]
related: []
---

# Learning: use `gh`'s advertised JSON field names

## Problem

A read-only `gh pr view --json` query used `autoMerge`; the installed CLI
rejected it and listed the supported field `autoMergeRequest`.

## Solution

Use the JSON field names from the installed command's schema or help output.
After a field error, rerun with the advertised field and verify the requested
state before reporting it.

## Key Insight

GitHub GraphQL concepts and `gh`'s JSON field names are not interchangeable.
