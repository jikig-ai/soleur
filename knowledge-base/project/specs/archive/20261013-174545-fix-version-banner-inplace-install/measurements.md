# Measurements — fix-version-banner-inplace-install

## Phase 0.0 premise probe (2026-10-13)

Method: a one-line `printf "$CLAUDE_PLUGIN_ROOT" >> /var/tmp/soleur-root-probe.<TAG>` was prepended to
`hooks/version-banner.sh` in BOTH the folder copy and the cache copy (byte-identical backups, restored with
`cp -p` and verified with `cmp`), then one `cd /tmp && claude -p "reply ok"` ran.

| Copy | Probe file written? | Observed `CLAUDE_PLUGIN_ROOT` |
|---|---|---|
| folder (`<top>/plugins/soleur`, marketplace source = directory) | yes | `/data/git-repositories/jikig-ai/soleur/plugins/soleur` |
| cache (`~/.claude/plugins/cache/soleur/soleur/e1bed15769a6`) | no | (hook never ran from the cache copy) |
| `--plugin-dir` | not run | loads the given directory by definition |

Outcome: premise holds (the hook root is the folder). Proceed with the plan.

## Side finding: `worktree-manager.sh sync-bare-files` prunes tracked dotfiles

Before the probe, `claude plugin list` reported `Status: failed to load / Marketplace soleur failed to load:
cache-miss` because the bare root had no `.claude-plugin/marketplace.json` (nor `.gitignore`, `.github`,
`.agents`, `.codex`, `.cursor-plugin`, `.grok`, ...). Cause: the prune step of `sync_bare_files` feeds
`comm -23` two `LC_ALL=C`-sorted streams WITHOUT `LC_ALL=C` on `comm` itself; under `LANG=en_US.UTF-8` it
prints `comm: file N is not in sorted order`, and the unreliable output deleted 1202 tracked files after the
checkout-index step had just restored them. The mirror was restored with an additive `checkout-index -a -f`
(no prune); after that `claude plugin list` shows `Read from: .../plugins/soleur`, `Status: enabled`.
This is a defect in a different subsystem and gets its own issue; it matters here because Phase 6 prescribes
`worktree-manager.sh sync`.
