---
title: "npm global install without sudo using --prefix ~/.local"
date: 2026-03-20
category: dependency-management
tags: [npm, permissions, PATH, global-install]
module: plugins/soleur/skills/agent-browser
---

# Learning: npm global install without sudo using --prefix ~/.local

## Problem

`npm install -g agent-browser@0.21.4` fails with EACCES when `/usr/lib/node_modules/` is owned by root. The Bash tool runs without sudo access per AGENTS.md rules.

## Solution

Install to `~/.local` prefix instead:

```bash
npm install --prefix ~/.local -g agent-browser@0.21.4
```

This creates the binary at `~/.local/bin/agent-browser`.

## Key Insight

1. `npm install --prefix ~/.local -g` is the standard no-sudo workaround for global npm packages
2. After installing, `~/.local/bin` must be **prepended** to PATH (not appended). If appended, an older system binary at `/usr/bin/` shadows the new one
3. Check PATH ordering with `which <tool>` — if it resolves to `/usr/bin/` instead of `~/.local/bin/`, the PATH order is wrong
4. In `.bashrc`, change `export PATH="$PATH:~/.local/bin"` to `export PATH="$HOME/.local/bin:$PATH"`

## Tags
category: dependency-management
module: plugins/soleur/skills/agent-browser
