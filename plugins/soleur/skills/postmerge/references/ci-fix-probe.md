# In-flight CI fix probe

Loaded by `soleur:postmerge` Phase 2 when CI fails on main, before writing a fix.

Look for a fix that is already in flight. For each file the fix would edit, run:

```bash
gh pr list --state open -L 100 --json number,title,files \
  --jq '.[] | select(any(.files[].path; . == "<path>")) | "\(.number) \(.title)"'
```

A hit may be a feature PR that carries the same fix under an unrelated title, so a search by title or
issue misses it. Read each hit's diff for that file before writing your own fix.

**Why:** #12782 duplicated a fix that #12705 already carried
(`knowledge-base/project/learnings/2026-11-16-web2-kernel-currency-replace-five-operational-traps.md` §1).
