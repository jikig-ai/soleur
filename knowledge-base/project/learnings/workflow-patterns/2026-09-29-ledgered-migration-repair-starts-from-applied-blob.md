---
title: Restore a ledgered migration from its applied blob before adding a follow-on
date: 2026-09-29
category: workflow-patterns
tags: [supabase, migrations, dev-ledger, git-object, rollback]
pr: 9051
---

# Learning: restore a ledgered migration from its applied blob before adding a follow-on

## Problem

The tenant-integration guard found `144_codex_auth_mode_rebind.sql` in the shared dev
ledger, but the path was absent from the PR tree and main. The exact applied blob still
existed in Git's object store. Renaming the newer `145` file back to `144` would not
repair parity because its content hash differed; leaving both out would strand the
shared database row.

## Solution

Restore the exact blob under the ledgered filename, then make the next numbered
migration a true delta from that schema. Preserve the predecessor's columns and
function signatures when applying and rolling back the delta. Pin the restored Git
blob identity in a focused test so later edits cannot silently recreate the drift.

Do not use a destructive earlier down migration to erase the orphan when later ledger
rows exist. If the applied bytes cannot be recovered, use the repository's explicit
reconciliation procedure and its per-command safety gates.

## Session Errors

1. **Read the predecessor migration from `origin/main`, where it did not exist.** It
   was part of the feature branch history. Recovery: read migration 143 from the
   feature commit that introduced it. **Prevention:** query the PR commit or the
   checked-out feature history when a ledgered migration belongs to an unmerged PR.
2. **A test patch used stale assertion context.** Recovery: reread the test and apply
   smaller edits. **Prevention:** anchor patches to the current file contents.
3. **The focused SQL test extractor matched only `CREATE FUNCTION`, then missed the
   safe `CREATE OR REPLACE FUNCTION` delta.** Recovery: accept either form. **Prevention:**
   test SQL function extractors against both creation and replacement syntax.
4. **A session-state patch targeted wording that was no longer present.** Recovery:
   reread the file tail and patch the current paragraph. **Prevention:** re-anchor a patch
   from the current file after any intervening edit.
