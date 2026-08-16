# Runbook — plugin delivery: stale install, failed refresh, destroyed checkout

Recovery for the three failure shapes in #7471. All figures cite
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/measurements.md`;
decision and rationale are in
[ADR-182](../../architecture/decisions/ADR-182-keyless-manifests-and-a-dedicated-marketplace-source.md).

**There is no telemetry from the delivery path.** When an install, refresh, or update fails on
a user's machine, nothing reaches this repo — no Sentry event, no log line, no marker. The user's
report is the only detection channel, and that is a property of the surface rather than an
oversight: the plugin runs on their machine, not ours. The daily drift alarm covers the published
*manifest* only, at up to 24 h latency, and says nothing about whether anyone's install succeeded.
The delivery canary (#7490) narrows that: it installs the published plugin in CI daily and asserts
delivered content, so a broken *published* delivery is now detected without a user report — but it
observes CI's install, not theirs. So when someone reports a delivery failure, treat their account as
the primary evidence — there is no dashboard covering their machine. Canary finding tokens are
tabulated at the end of this runbook.

**Scope matters in every command here.** `claude plugin install|update|uninstall` defaults to
`--scope user`. A bare `claude plugin update soleur@soleur` therefore targets the *user*-scope
install and silently finds nothing when the real install is project-scoped. Read the scope first:

```bash
claude plugin list          # shows Scope per installed plugin
```

The live operator install is `scope: project` against the operator's own project checkout
(`claude plugin list` prints the path). Pass `--scope project` to every command below when
operating on it.

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
P=$(claude plugin list --json | jq -r '.[] | select(.id|startswith("soleur@")) | .installPath')
ls "$P/scripts/lib/session-state.sh"      # present since #7426
ls "$P/skills" | wc -l                     # compare against the source tree
```

Do not verify via `installed_plugins.json` alone. Upstream #76882 means the metadata does not
reliably follow the content, and it was measurably stale on the operator machine while this was
being written.

**The two `ls` assertions above are content-based and correct. The PATH they run against is not
independent of the metadata this block warns about.** `claude plugin list --json` is a **projection
of `installed_plugins.json`** — verified by editing that file and watching the CLI print the edited
value back verbatim — so `$P` is a metadata read wearing a CLI's clothes. Stale metadata names an
older cache directory, and the assertions then describe a directory that is not the live install.
Cross-check `$P` against the cache directory as it exists on disk, which the CLI does not mediate:

```bash
ls -dt ~/.claude/plugins/cache/soleur*/*    # newest first; $P should be among these
echo "$P"
```

If `$P` is absent from that listing, or is not the newest entry, treat the metadata as stale: run the
content assertions against the newest directory as well, and only trust a verdict the two agree on.

---

## Symptom 2 — `marketplace update` / `add` times out on `jikig-ai/soleur`

Expected on the legacy whole-repo channel and **not a transient fault**: the clone measured
**329 s** against the CLI's 120,000 ms default (§1.6/2B.6), i.e. ~2.7× over. It cannot succeed at
the default.

Which operation pays that 329 s matters for what to do next. A steady-state refresh of an existing
checkout is an incremental `git pull` — the reflog on the live install records one clone followed by
repeated `Fast-forward` pulls — so a *refresh* is normally cheap. The 329 s is paid on the **initial
`marketplace add`**, and on any refresh the CLI cannot reconcile in place and therefore restarts as
a full re-clone. Adding `--sparse` to an existing checkout is one way to force exactly that; see the
two `--sparse` cases below before running anything.

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

**Reclaim the orphan — only the CACHE is orphaned.** Measured on the real migration (2026-08-12,
#7489): `marketplace remove` reclaimed the **378 MiB marketplace checkout itself**, so there is
nothing to do about that directory. What survived is the plugin **cache** — **26 MiB** on the
operator machine, not the ~9.6 MiB this runbook previously quoted, because the cache directory is
named for the resolved version and the resolved version is now a commit SHA, so **every update
materialises a new directory and leaves the previous one behind**. Expect the figure to be larger
the longer the install has been updating; two version directories had accumulated here. There is no
CLI verb to reclaim it. The old and new cache directories differ by one suffix, so print the path
before deleting:

Only once `claude plugin list` shows `soleur@soleur-marketplace` and no `soleur@soleur`. Ask
the CLI which paths are live, and delete only what is not among them:

```bash
claude plugin list --json | jq -r '.[].installPath'
```

```bash
rm -rf ~/.claude/plugins/cache/soleur
```

Deliberately two blocks: a single fenced block gets one copy button in every renderer, which
would execute the check and the delete in the same paste and defeat the check.

A `~/.claude/plugins/marketplaces/soleur.bak` may also be present — the issue reported one at
374 MiB. **Do not delete it while Symptom 3 is a possibility:** if such a `.bak` exists it is the
primary recovery source below. Reclaim it only once `claude plugin list` shows a working install on
the new marketplace.

- `unverified:` **that a failed refresh destroys the checkout.** Three independent forced-failure
  instruments on CLI 2.1.228 — an aborted `--sparse` add, a `marketplace update` against a
  nonexistent remote, and a clone failing mid-flight through an unroutable proxy — each left the
  checkout **and a planted sentinel file intact**, and **no `.bak` appeared** in any of them. The
  `.bak` rename exists as a string in the 2.1.228 bundle, but the branch never executed here, so the
  destruction risk is recorded as **not reproduced on this version**, not as refuted and not as
  asserted. The warning above stays because the asymmetry favours it: deleting a `.bak` that turns
  out to have been the only copy is unrecoverable, and leaving one in place costs disk.

**If the legacy channel must be kept, `--sparse` depends on whether a checkout already exists —
and the two cases are opposite.**
`claude plugin marketplace add` accepts `--sparse <paths...>` (git sparse-checkout).

*Case 1 — no `~/.claude/plugins/marketplaces/soleur` yet (a FRESH add). Safe, and the fast path.*
Measured (§1.4): **78 s and 16.98 MiB at the default timeout**, against 329 s and 342.7 MiB plain —
so it works *inside* the CLI's own limit instead of arguing with it:

```bash
claude plugin marketplace add jikig-ai/soleur --sparse .claude-plugin plugins
claude plugin install soleur@soleur
```

*Case 2 — a plain `~/.claude/plugins/marketplaces/soleur` already exists. Do NOT run the command
above.* Applying `--sparse` to an **existing checkout** does not reconcile it in place: it forces a
**full re-clone**. Measured three independent ways on 2026-08-12 (#7489) — a sentinel planted inside
the checkout disappeared, the `.git` inode changed, and `.git/info/sparse-checkout` appeared. The
inode change is what rules out the sentinel merely having been deleted. That measurement used the
232 KiB marketplace repo and took 8 s; **against the 181 MiB monorepo the same forced re-clone is
the 329 s operation, which cannot complete under the CLI's 120 s default.** So on the legacy channel
this instructs a stranded user into an operation that will not finish. Migrate instead (preferred
fix, above). If the legacy entry genuinely must be kept, raise the timeout for that one invocation
rather than reaching for `--sparse`:

```bash
CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=900000 claude plugin marketplace add jikig-ai/soleur --sparse .claude-plugin plugins
```

Raising the timeout is also the right tool when the checkout already exists and only needs
refreshing — which is an incremental `git pull`, not a clone, so it is normally fast and the raised
value only covers the case where the CLI falls back to a re-clone:

```bash
CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=900000 claude plugin marketplace update soleur
```

Prefer `marketplace update` over `remove` → `re-add`: it is the non-destructive route and it is the
one measured to work. Demote `remove → re-add → reinstall` to the case below, where the checkout is
already destroyed.

**`claude plugin install --url …` does not exist** on CLI 2.1.227 (`error: unknown option '--url'`),
despite having been documented here previously. Do not reach for it; use `marketplace add`.

---

## Symptom 3 — the marketplace checkout is destroyed

Shape: `~/.claude/plugins/marketplaces/soleur/` holds only a `.git` with one object, no packs, no
HEAD; or a later invocation removed the directory and its `.bak` sibling. The plugin keeps loading
from cache, so nothing surfaces until a command reports `Marketplace soleur failed to load:
cache-miss`.

1. **Look for the `.bak` first.** A `.bak` did not appear in any forced-failure instrument on 2.1.228
   (see the `unverified:` bullet under Symptom 2), so do not expect one — but if
   `~/.claude/plugins/marketplaces/soleur.bak` does exist, restore it rather than re-cloning:

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

`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` per-invocation is fine for recovery. Making it persistent is a
different question, and it was instrumented on CLI 2.1.228 (2026-08-12, #7489). Every claim below
carries its evidential status; the readings are in
`knowledge-base/project/specs/feat-one-shot-7489-7490-marketplace-retire-delivery-followups/measurements.md`.

- `measured:` **an `env` block in `~/.claude/settings.json` DOES reach the plugin git path.** Two
  runs against the same scratch `HOME`, differing only in the settings file and with no
  `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` in either process environment:
  `{"env":{"CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS":"1"}}` failed in 4 s with `Git clone timed out`,
  while `{}` — the positive control, which is what makes the result attributable — succeeded in 10 s.
- `unverified:` **whether that same `env` block reaches the BACKGROUND refresh**, which is the half
  that actually matters, because the background refresh runs without the operator's shell. There was
  no deterministic instrument: with `lastUpdated` backdated and `autoUpdate: true`, a
  `claude plugin list` left `lastUpdated` unchanged, so `plugin list` does not trigger a refresh. The
  foreground result is explicitly **not** generalised to it — `marketplace add` is a different call
  path. Verifying it needs a real session start against a backdated scratch `HOME`.
- `measured:` **`autoUpdate: false` PERSISTS.** A hand-written `false` in a scratch
  `known_marketplaces.json` survived a subsequent CLI invocation byte-identically, `lastUpdated`
  included. (Incidental: a *fresh* `marketplace add` on 2.1.228 records `autoUpdate: null`, not
  `true`.)
- `unverified:` **whether `autoUpdate: false` SUPPRESSES the refresh, and which of the two
  declaration sites — `~/.claude/settings.json` or `~/.claude/plugins/known_marketplaces.json` — is
  authoritative when they disagree.** Both questions need an observable refresh, and the bullet above
  establishes there is no deterministic trigger. Persisting is not the same as taking effect.
- `unverified:` **`CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE` has no differentiable effect on
  this version** — not because it was measured inert, but because the branch it governs never ran.
  Both arms, set and unset, produced identical results in all three forced-failure instruments (see
  the `unverified:` bullet under Symptom 2). Do not recommend it as a mitigation: there is no reading
  that shows it doing anything.

**Conclusion, and it is the honest one rather than the tidy one.** Since the background-refresh half
is unverified, there is **no persistent mechanism this runbook can vouch for**. Do not tell a user to
set an `env` block and consider the problem solved — that would assert a claim about the background
path from a foreground measurement. **Migrating off the legacy channel is the reliable answer**: it
removes the 181 MiB refresh entirely, so no timeout needs to persist. Use the per-invocation variable
for recovery, and migrate.

---

## Delivery-canary findings — what each token means

`scheduled-marketplace-drift.yml`'s canary job files its verdict as a GitHub issue naming one or more
of these tokens. Rationale for the canary itself is ADR-182, Decision 6; this table is lookup only.

| Token | What was observed | First move |
|---|---|---|
| `content_mismatch` | A delivered file's digest differs from the same path fetched from the repo at the commit the install resolved. | Treat as a delivery-integrity fault, not a manifest fault. Compare the named paths by hand before touching the manifest. |
| `incomplete_delivery` | The delivered file **set** is smaller than what `main` serves under `plugins/soleur`. This is the shape of the original defect — 64 skills delivered against 96 at source. | Check the marketplace entry's `source.path` and `source.source`; a subtree or source-type change under-delivers silently. |
| `stale_delivery` | The install resolved a commit that is not `main` HEAD. | Confirm `main` HEAD, then check the entry is still unpinned — a `ref`/`sha`/`tag` freezes new installs. |
| `install_failed` | `claude plugin install` returned non-zero in CI. | Read the recorded rc and the CLI output in the run log; this is upstream of every content assertion, so nothing else in the run is evidence. |
| `installpath_unresolved` | The install path could not be resolved, so the canary compared **nothing**. Reported as a failure, never as "no differences". | Check whether the install step actually ran; a zero-comparison run is a broken instrument, not a green delivery. |
| `reference_unreadable` | The reference listing or a reference file came back empty or as a non-conforming body (e.g. an HTML error page). | The comparison had no baseline. Fail closed, re-run, and check GitHub API reachability and rate limits from the runner. |
| `cli_unavailable` | The pinned Claude Code CLI could not be obtained, so no install was attempted. | An acquisition problem, not a delivery problem. Nothing about the published plugin is established by this run. |
