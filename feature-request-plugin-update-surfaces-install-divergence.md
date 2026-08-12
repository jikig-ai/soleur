# Feature Request: `plugin marketplace update` should surface (or resolve) install divergence

**Repository:** https://github.com/anthropics/claude-code

## Problem

Updating an installed plugin is two steps, and the first one gives no signal that a second is
required:

```bash
claude plugin marketplace update <name>   # advances ~/.claude/plugins/marketplaces/<name>
claude plugin install <name>              # re-pulls ~/.claude/plugins/cache/<name>/…
```

`marketplace update` moves the marketplace checkout to the new HEAD and reports success. It
does not re-pull the plugin install, which retains its own `gitCommitSha` and `lastUpdated`
in `installed_plugins.json`. Because `${CLAUDE_PLUGIN_ROOT}` resolves to the **install**, not
the marketplace checkout, the two can diverge silently and indefinitely.

The failure mode this produces is worse than a plain stale version, because the obvious
verification step confirms the wrong tree:

1. A fix ships upstream.
2. The user runs `marketplace update`, which succeeds.
3. The user inspects the marketplace checkout — the fix is present.
4. Every actual run still executes the old install, so the fix appears not to work.

Measured on a real install: the marketplace sat at `98ad03a` while `installed_plugins.json`
recorded `gitCommitSha: f449cb6a…`, `lastUpdated` four months earlier. It took an explicit
`plugin install` to converge them. Reported downstream as jikig-ai/soleur#7474, where the
divergence surfaced as an unattributed `Module not found` from a plugin script that existed
in the marketplace copy but not in the install.

## Proposed Solution

Any one of these would close it; they are listed cheapest-first.

1. **Warn on divergence.** When `marketplace update` finishes and an installed plugin from
   that marketplace is at a different commit, print the two SHAs and the command that
   converges them. This is purely additive and needs no behaviour change.
2. **Expose the comparison.** Give `claude plugin list` (or a `claude plugin status`) an
   installed-vs-available column, so the divergence is inspectable without reading
   `installed_plugins.json` by hand. Today there is no supported way to ask this question —
   which is also why downstream tooling cannot check it for the user.
3. **Offer to update.** Prompt (or accept `--update-installed`) to re-pull installed plugins
   as part of `marketplace update`.

Option 1 alone would have prevented the downstream incident.

## Why this is not fixable downstream

A plugin cannot reliably self-diagnose this. The install is not a git checkout
(`git rev-parse HEAD` fails there), so the only SHA source is `installed_plugins.json`; and
the marketplace checkout directory name is not derivable from the marketplace key — an
install keyed `soleur@soleur` sat beside directories named `jikig-ai-soleur` and
`soleur.bak`, with no `soleur`. Any downstream check would have to hardcode paths outside its
own plugin root and guess at undocumented layout, which is the class of hand-resolution that
caused the original bug.
