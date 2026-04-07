---
category: security
module: web-platform/server
tags:
  - CWE-59
  - symlink
  - directory-traversal
  - filesystem
date: 2026-04-07
---

# Learning: Symlink escape in recursive directory traversal

## Problem

When building a file tree or collecting files recursively for search, using `fs.Dirent.isDirectory()` and `fs.Dirent.isFile()` follows symlinks transparently. A symlink directory inside the knowledge-base pointing to `/etc/` or another user's workspace would be traversed, and its files would be returned in results — even when the single-file content endpoint correctly validates paths via `isPathInWorkspace()`.

The gap: `readContent` validates each requested path through `isPathInWorkspace()` (which resolves symlinks via `realpathSync`), but `buildTree` and `collectMdFiles` scan directories without checking containment. The security boundary was applied to point reads but not to directory enumeration.

## Solution

Add `!entry.isSymbolicLink()` checks alongside `isDirectory()` and `isFile()` in recursive traversal functions:

```typescript
if (entry.isDirectory() && !entry.isSymbolicLink()) {
  // recurse
} else if (entry.isFile() && !entry.isSymbolicLink() && entry.name.endsWith(".md")) {
  // include file
}
```

Knowledge-base files should never be symlinks — they are created by agents and committed to git. Skipping symlinks entirely is simpler and more correct than resolving each one through `isPathInWorkspace`.

## Key Insight

When a module has both point-access functions (read a specific file) and enumeration functions (list all files), security checks must cover both paths. It is easy to validate point access (the path comes from user input) and forget that enumeration discovers paths automatically — an attacker plants a symlink, and enumeration follows it without any user-supplied path to validate.

The defense-in-depth pattern: (1) point access validates via `isPathInWorkspace`, (2) enumeration skips symlinks via `!entry.isSymbolicLink()`, (3) negative-space security tests verify both patterns are present.
