---
title: Unverified Pencil Desktop bundle ID in check_deps.sh
date: 2026-03-03
category: technical-debt
tags: [pencil, macos, dependency-detection]
severity: low
synced_to: [pencil-setup]
---

# Unverified Pencil Desktop Bundle ID

## Problem

`plugins/soleur/skills/pencil-setup/scripts/check_deps.sh:28` contains a TODO acknowledging an unverified assumption:

```bash
# TODO: verify bundle ID 'dev.pencil.desktop' against actual Pencil.app Info.plist
mdfind "kMDItemCFBundleIdentifier == 'dev.pencil.desktop'" 2>/dev/null | grep -q . && return 0
```

If the actual Pencil Desktop bundle ID differs, the macOS detection path silently fails and falls back to PATH-based detection.

## Key Insight

This is the only actionable TODO in the entire TypeScript and shell codebase. Low risk since PATH-based fallback works, but should be verified against a real Pencil Desktop installation on macOS.

## Tags

pencil, macos, dependency-detection
