# Runbook — plugin delivery: stale install, failed refresh, destroyed checkout

Recovery for the three failure shapes in #7471. All figures cite
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/measurements.md`;
decision and rationale are in
[ADR-182](../../architecture/decisions/ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md).

**Scope matters in every command here.** `claude plugin install|update|uninstall` defaults to
`--scope user`. A bare `claude plugin update soleur@soleur` therefore targets the *user*-scope
install and silently finds nothing when the real install is project-scoped. Read the scope first:

```bash
claude plugin list          # shows Scope per installed plugin
```

The live operator install is `scope: project`, `projectPath /home/jean/git-repositories/skouer/Skouer`.
Pass `--scope project` to every command below when operating on it.

**Plugin changes apply on CLI restart.** `claude plugin update --help` says so explicitly. An
update that reports success and appears to change nothing is usually an un-restarted CLI, not a
failed update.

---

## Symptom 1 — `plugin update` says "already at the latest version" but nothing changes

The historical cause is fixed at source: the manifests no longer carry a `version` key, so the
CLI records the commit SHA as the version and the comparison detects new commits (ADR-182).

If it recurs, the first thing to check is whether a `version` key came back:

```bash
curl -fsSL https://raw.githubusercontent.com/jikig-ai/soleur-marketplace/main/.claude-plugin/marketplace.json \
  | jq '.plugins[0] | has("version")'      # MUST print false
```

`true` means the distribution manifest regressed. `scheduled-marketplace-drift.yml` alarms on this
daily; fix it in `jikig-ai/soleur-marketplace` and re-run the update. A `version` key is the defect,
not a cosmetic difference.

Then confirm the install actually advanced — **on content, not on metadata**:

```bash
P=$(claude plugin list --json 2>/dev/null | jq -r '.[] | select(.name=="soleur") | .installPath')
ls "$P/scripts/lib/session-state.sh"      # present since #7426
ls "$P/skills" | wc -l                     # compare against the source tree
```

Do not verify via `installed_plugins.json` alone. Upstream #76882 means the metadata does not
reliably follow the content, and it was measurably stale on the operator machine while this was
being written.

---

## Symptom 2 — `marketplace update` / `add` times out on `jikig-ai/soleur`

Expected on the legacy whole-repo channel and **not a transient fault**: the clone measured
**329 s** against the CLI's 120,000 ms default (§1.6/2B.6), i.e. ~2.7× over. It cannot succeed at
the default.

**Preferred fix — migrate off the whole-repo channel.** This never re-clones the monorepo, so it
works *from* the broken state and needs no raised timeout (all four commands measured green at the
default, §1.6/2B.6):

```bash
claude plugin marketplace add jikig-ai/soleur-marketplace
claude plugin install soleur@soleur-marketplace
claude plugin uninstall soleur@soleur
claude plugin marketplace remove soleur
# restart the CLI
```

Add `--scope project` to each if that is the install's scope.

**Reclaim the orphan.** `uninstall` and `marketplace remove` both succeed while leaving the old
plugin cache behind — ~9.6 MiB, with no CLI verb to reclaim it (§1.6/2B.6). The old and new cache
directories differ by one suffix, so print the path before deleting:

```bash
ls -d ~/.claude/plugins/cache/soleur       # the OLD entry
rm -rf ~/.claude/plugins/cache/soleur      # NOT .../cache/soleur-marketplace
```

The same class explains the 374 MiB `soleur.bak` orphan in the issue; check for it too.

**Stopgap if the legacy channel must be used** (raises the timeout for one invocation):

```bash
CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=900000 claude plugin marketplace update soleur
```

Prefer `marketplace update` over `remove` → `re-add`: it is the non-destructive route and it is the
one measured to work. Demote `remove → re-add → reinstall` to the case below, where the checkout is
already destroyed.

---

## Symptom 3 — the marketplace checkout is destroyed

Shape: `~/.claude/plugins/marketplaces/soleur/` holds only a `.git` with one object, no packs, no
HEAD; or a later invocation removed the directory and its `.bak` sibling. The plugin keeps loading
from cache, so nothing surfaces until a command reports `Marketplace soleur failed to load:
cache-miss`.

1. **Look for the `.bak` first.** The updater moves the existing checkout aside before re-cloning.
   If `~/.claude/plugins/marketplaces/soleur.bak` still exists, restore it rather than re-cloning:

   ```bash
   ls -d ~/.claude/plugins/marketplaces/soleur.bak && \
     mv ~/.claude/plugins/marketplaces/soleur.bak ~/.claude/plugins/marketplaces/soleur
   ```

2. **Otherwise migrate to the new channel** (Symptom 2, preferred fix). Re-adding costs ~39 KB
   rather than 181 MiB, which is what makes recovery cheap — it is also why ADR-182's rollback is
   `remove → re-add → reinstall` rather than "revert the source", since a source-side revert would
   have to travel through the broken refresh to reach anyone.

3. **Only if the legacy entry must be restored**, with the raised timeout:

   ```bash
   CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=900000 claude plugin marketplace add jikig-ai/soleur
   CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=900000 claude plugin install soleur@soleur
   ```

Restart the CLI after any of these.

---

## Making the timeout persistent

`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` per-invocation is fine for recovery but does not help the
background `autoUpdate` refresh, which runs without the operator's shell. Whether an `env` block in
`~/.claude/settings.json` reaches the plugin git path **and** that background refresh was not
established at time of writing — treat it as unverified rather than assuming it works, and prefer
migrating off the legacy channel, which removes the need entirely.
