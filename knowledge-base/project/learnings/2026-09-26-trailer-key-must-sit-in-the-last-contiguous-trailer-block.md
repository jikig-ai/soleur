---
title: A trailer gate read my key and still failed — %(trailers:key=) only sees the LAST contiguous trailer block
date: 2026-09-26
category: workflow-patterns
pr: 8868
---

A commit carrying `Rename-Allowed-By: <name>` failed `rename-guard` anyway.
The commit body was fine; the problem was *where in the body* the trailer
sat. `git log --format='%(trailers:key=K,valueonly)'` parses only the last
contiguous run of `Key: value` lines at the end of the message, and my
`Generated with [Devin](…)` attribution line — which is not a trailer —
split the block, stranding `Rename-Allowed-By` in what the parser treats as
prose.

Message shape that fails:

```
Subject

Body…

Rename-Allowed-By: Name

Generated with [Devin](https://devin.ai)

Co-Authored-By: Devin <…>
```

`%(trailers)` sees only `Co-Authored-By`. Working shape keeps every gate
trailer inside the final block, after the attribution prose:

```
Subject

Body…

Generated with [Devin](https://devin.ai)

Rename-Allowed-By: Name
Co-Authored-By: Devin <…>
```

Verify before pushing — one line:

```bash
git log --format='%(trailers:key=Rename-Allowed-By,valueonly)' -1 HEAD
```

Two adjacent facts from the same session, both about merge commits and
guard scans:

- `rename-guard`'s per-commit scan diffs merge commits against their first
  parent, so a BEHIND-sync merge surfaces every main-side add+delete as
  rename candidates. Git's 5% similarity heuristic pairs unrelated files
  (a deleted workflow YAML and an added spec `tasks.md` scored R006), and
  the pair is re-attributed to your PR. The sanctioned vouch is a
  `Rename-Allowed-By:` trailer commit — and it only works if the trailer
  lands in the final block per the rule above. Precedent commits:
  `git log --grep='vouch for the main-side rename'`.
- On a busy main, `BEHIND → sync → 40-min CI → BEHIND again` is a
  treadmill. Keep auto-merge armed and keep syncing; the window closes
  only when a full CI pass lands inside a quiet stretch. Budget the
  session accordingly — three syncs before merge is normal, not a signal
  that anything is wrong.
