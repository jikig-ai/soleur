# Hook-Test Feature-Branch-CWD Blind Spot

Loaded by `work` Phase-2 suite-fixture guidance. A `.claude/hooks/*.test.sh`
whose outcome depends on a CWD/branch-resolved gate (`block-commit-on-main`
via `git rev-parse --abbrev-ref HEAD`, `git worktree list` counts,
`symbolic-ref HEAD`) passes on the `feat-*`/`fix-*` worktree every local run
uses, but post-merge CI runs on the merged `main` commit and can fail ONLY
there (`block-commit-on-main` denies a `git commit`-shaped fixture input →
masks the gate under test). The local 104/104 is NOT authoritative for these.

When the diff touches `.claude/hooks/*.test.sh`, run the suite once from a
throwaway committed-`main` CWD:

```bash
d=$(mktemp -d -t soleur-run.$$.XXXXXXXX)   # signed root — reapable on a miss (#10017)
git -C "$d" init -q -b main && git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
(cd "$d" && bash <repo>/.claude/hooks/<file>.test.sh)
```

(`git init` AT the root is depth-1 → the nested-git retain conjunct does not
fire; the dir stays reapable.) Fix-side: isolate the test from the
orthogonal gate by running the hook from a non-git/pinned-branch CWD, not
the ambient process CWD. **Why:** #5192 — guardrails AC1/AC3/AC4 passed
104/104 locally, turned main red, fixed in #5209.
