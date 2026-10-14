# Measurement Record — feat-one-shot-7471-plugin-delivery-path

Single source for every measured number this feature asserts. The plan, the ADR, and the PR body
cite **this file by section anchor** rather than restating figures — a number restated in four
places drifts in four places.

Append-only. Correct a reading by adding a new dated section that cites the old one; never edit a
recorded reading's body.

---

## 1.0 — Falsification gate: does `git-subdir` avoid the whole-repo clone?

**Run 2026-08-12. Verdict: PASS on both clauses.** Outcome (b) stands; Phase 2B is unblocked.

This is the gate the UC-1 resolution rests on. Its premise — that a `git-subdir` marketplace entry
materialises only the named subtree — was sourced from one sentence of Anthropic's documentation
and had never been measured. See `decision-challenges.md` §UC-1 for why it gates the run.

### Method

Clean `HOME` (`mktemp -d`, so nothing pre-existing is counted), `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS`
**unset** so the CLI's own 120,000 ms default applies. Scratch marketplace named `gate10`, one
plugin entry, no `version` key:

```json
{ "name": "soleur",
  "source": { "source": "git-subdir",
              "url": "https://github.com/jikig-ai/soleur.git",
              "path": "plugins/soleur" } }
```

```
claude plugin marketplace add  <scratch>/src
claude plugin install soleur@gate10 --scope project
du -sb "$HOME/.claude/plugins/marketplaces" "$HOME/.claude/plugins/cache"
```

CLI `2.1.227`, git `2.53.0`. Source commit `325a1a5c0149c51c200055543794db23917cbc37`.

### Clause 1 — byte count

| Measurement | Value |
|---|---|
| `plugins/marketplaces` | 0 B (local-path source; a published repo adds its own ~50 KB) |
| `plugins/cache` | **10,093,045 B = 9.63 MiB** |
| **Total** | **10,093,045 B** |
| Threshold (fail-closed) | 52,428,800 B (50 MiB) |
| Margin | **5.2× under** |

Contrast: 181.37 MiB pack / 215.4 MiB tree for the whole repository today.

The reading came in **below** the 16.98 MiB plain-git floor recorded in the plan's
`## Amendment 2026-08-12`. That is consistent rather than contradictory — the floor was measured
with `.git` present (partial + shallow + sparse), and the CLI materialises **no `.git` at all**.

### Clause 2 — the default timeout

Both commands completed with the variable unset: `marketplace add` **1 s**, `install` **37 s**
against the 120 s default. P5b ("completes within the default timeout") is bought, not merely P5a.

### The subtree boundary is real, not approximate

891 files materialised against 894 tracked under `plugins/soleur`. Verified as a boundary rather
than a size coincidence — `knowledge-base/` and `scripts/` exist at *both* levels, so basename
presence proves nothing and the counts were compared directly:

| Path | In cache | `plugins/soleur/<p>` | repo root `<p>` |
|---|---|---|---|
| `knowledge-base` | 16 | 16 | 9,045 |
| `scripts` | 15 | 15 | 292 |

Repo-root-only markers all absent: `AGENTS.rules.md`, `CONTRIBUTING.md`, `package.json`,
`.mcp.json`, `apps/`, `.github/`.

This is what retires the Art. 5(1)(c) / Art. 25(2) minimisation finding **by construction**: the
Art. 30 register and the 41 counsel-review memoranda live under repo-root `knowledge-base/`, which
is not delivered.

### The payload is current, which is the whole point of the issue

`skills/` = **96** (the stale install measured in the issue had 64), and
`scripts/lib/session-state.sh` is **present** (absent from the stale install). The delivery path
carries what the source has.

### Values downstream tasks consume

- **`installPath`** = `<home>/.claude/plugins/cache/<marketplace-name>/soleur/0.0.0-dev` — three
  segments: marketplace `name`, plugin `name`, version. Task 2B.4 and the ADR-178 reconciliation
  (4.5) consume this measured string, not an inferred one.
- **`installed_plugins.json` is an array per plugin id**, keyed `soleur@gate10`, each element
  carrying `scope` / `installPath` / `projectPath`. Index it with a scope selector (task 6.4).
- **`gitCommitSha` = `325a1a5c…` was recorded.**

### Finding the gate was not looking for

`gitCommitSha` was recorded **even though the manifest still carries `"version": "0.0.0-dev"`**
(the clone is of `main`, pre-fix). So SHA *recording* is not conditional on a keyless manifest
under a `git-subdir` source — the two are independent. This does **not** weaken Phase 2: the issue's
defect is that `plugin update` **compares version strings** and short-circuits, which is about the
comparison, not about whether a SHA was written. It does mean the version segment of the cache path
above is still `0.0.0-dev` here, and Phase 2 is what changes it. Task 1.2's migration fixture is
what measures the comparison; do not read this row as having pre-empted it.

---

## 2B — The published marketplace, measured against the real repo

**Run 2026-08-12, immediately after `jikig-ai/soleur-marketplace` was created and pushed.**
This is §1.0 re-run against the **shipped article** rather than a local-path fixture — a fixture
passing while the published thing fails is the exact gap this plan exists to close.

Clean `HOME`, `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` unset, unauthenticated:

```
claude plugin marketplace add jikig-ai/soleur-marketplace
claude plugin install soleur@soleur-marketplace --scope project
```

| | Value |
|---|---|
| `marketplace add` | **13 s** (the monorepo path exceeds the 120 s default and destroys the checkout) |
| `install` | **33 s** |
| `plugins/marketplaces` | 39,188 B — the repo's whole cost |
| `plugins/cache` | 10,093,043 B |
| **Total** | **10,132,231 B = 9.66 MiB** (threshold 50 MiB) |

**Plugin ID: `soleur@soleur-marketplace`.** The `@` half comes from the manifest's `name` field,
not the repo name — they coincide here by choice. `installPath` =
`<home>/.claude/plugins/cache/soleur-marketplace/soleur/0.0.0-dev`; `gitCommitSha` recorded.

**Defect 2 is resolved for new installs**, measured on the published repo rather than asserted.

The version segment still reads `0.0.0-dev` because `plugins/soleur/.claude-plugin/plugin.json`
on `main` still carries the key — Phase 2 is what changes that, and task 6.5 re-runs this after
merge. Do not read this row as having verified Phase 2; it verifies distribution only.

---

## 1.9 — What the `version` key actually does (controlled, and it refutes §1.0's inference)

**Run 2026-08-12. This supersedes the mechanism stated in §1.0's "Finding the gate was not looking
for" and every corpus site that cited it. §1.0's readings stand; its *inference* does not.**

### Why this was run

A claim propagated through the governance corpus and the published marketplace README: *a `version`
key's presence suppresses `gitCommitSha` tracking.* It came from a control-group correlation in
`installed_plugins.json` — six keyless official plugins carrying a SHA, two versioned ones showing
`sha=NONE`. It was never tested, and the control group is heterogeneous (different source shapes,
different authors, different CLI versions at install time).

Two counterexamples surfaced before the experiment:

- **`code-review`** — plugin manifest **keyless**, yet `sha=NONE`, with `version` recorded as
  `15b07b46dab3` (a commit string in the version field).
- **§1.0's own gate10 run** — plugin manifest **versioned**, yet a `gitCommitSha` **was** recorded.

One counterexample in each direction means the correlation is not the mechanism.

### The experiment

Two arms, identical in every respect except the plugin manifest's `version` key. Marketplace entry
keyless in **both** arms; relative-path source, matching the control group's shape; clean `HOME`
per arm; same CLI.

| Arm | `plugin.json` `version` | `gitCommitSha` | recorded `version` |
|---|---|---|---|
| with-version | `"0.0.0-dev"` | **YES** | `0.0.0-dev` |
| keyless | absent | **YES** | `bfc681c7d8c7` |

### The finding

**A `version` key does not suppress `gitCommitSha`. Both arms record one.** What the key changes is
the **recorded version string**: with the key it is the constant from the manifest; without it the
CLI records **the commit SHA as the version**.

That is the actual defect mechanism, and it is simpler than the one it replaces:

> `claude plugin update` compares **version strings**. A constant `0.0.0-dev` always compares equal,
> so the update short-circuits, reports "already at the latest version", and exits 0 having
> delivered nothing. A SHA-valued version changes with every commit, so the comparison sees a
> difference and the update applies.

This matches the issue's own evidence exactly — `✔ soleur is already at the latest version
(0.0.0-dev)`, exit 0 — which the suppression story never explained.

It also explains `code-review`: a keyless manifest whose SHA landed in `version` and not in
`gitCommitSha`. The CLI has more than one recording mode; **which field carries the identity is not
the load-bearing part — whether the identity string CHANGES between commits is.**

### Consequence

Every site asserting the suppression mechanism is wrong and must state the comparator instead. The
conclusion — *do not add a `version` key to any of the three manifests* — is unchanged and, if
anything, better supported: it now rests on a measured comparator rather than an inferred one.

---

## 1.6 / 2B.6 — Full migration rehearsal, legacy install → new marketplace

**Run 2026-08-12 on a clean `HOME`, end to end, no shortcuts.** Task 1.6 asked for a real refresh
from the real migration state rather than a fixture; this is that run, and it doubles as the
verification of the migration sequence published in both READMEs.

### Step 1 — establish a genuine legacy install

| | Value |
|---|---|
| `marketplace add jikig-ai/soleur` (timeout raised to 900,000 ms) | **329 s** |
| `install soleur@soleur` | 2 s |
| Total `~/.claude/plugins` | **359,399,529 B = 342.7 MiB** |

**329 s is the finding.** The CLI's default is 120,000 ms, so the documented install path takes
**~2.7× longer than the timeout allows**. Defect 2 is not marginal or network-dependent — the
default cannot succeed here, which is why the failure is reproducible rather than flaky.

### Step 2 — the published migration sequence, default timeout UNSET

| Command | Result |
|---|---|
| `marketplace add jikig-ai/soleur-marketplace` | rc=0, **6 s** |
| `install soleur@soleur-marketplace` | rc=0, **28 s** |
| `uninstall soleur@soleur` | rc=0 |
| `marketplace remove soleur` | rc=0 |

All four succeed **with no raised timeout**, because the sequence never re-clones the monorepo.
That is the property task 2B.6 required — a migration usable *from* the broken state, rather than
one that must first traverse the thing that is broken.

### Step 3 — end state is correct

`plugin list` shows only `soleur@soleur-marketplace`; `marketplace list` shows only
`soleur-marketplace`. The 181 MiB marketplace checkout is reclaimed (`plugins/marketplaces` back
to 39,188 B — the new repo's whole footprint).

### The orphan the migration leaves behind (task 3.6's class, measured)

`plugins/cache` ends at **20,186,220 B**, roughly double the ~10 MiB the new install needs:
`cache/soleur/soleur` survives `uninstall` **and** `marketplace remove`. About **9.6 MiB** of
orphaned plugin cache, never garbage-collected.

Modest in absolute terms and worth documenting rather than automating away — but it means
"removed the marketplace" does not mean "reclaimed the disk", and the same class explains the
374 MiB `soleur.bak` orphan the issue reported. The reclaim is a manual `rm -rf` of the stale
cache directory; there is no CLI verb for it.

---

## 1.2 / 1.3 — The migration shape: does the fix reach an EXISTING install?

**Run 2026-08-12. Verdict: yes, and it keeps working. CPO blocking condition C1 is discharged.**

Everything before this measured *fresh* installs. The control group proves keyless manifests update
correctly when installed keyless **from the start** — but no existing install is in that state. Every
one of them has a recorded `"version": "0.0.0-dev"` in `installed_plugins.json` meeting a manifest
that no longer has the key. Until this run, P1 was **verified for new installs and merely asserted
for upgrades**, and upgrades are the entire population.

Fixture: a local git marketplace, plugin installed **with** the sentinel, then the key removed at
source and the content changed — the exact transition this PR performs.

| Stage | recorded `version` | cache dir | delivered content |
|---|---|---|---|
| **A** — installed with sentinel (pre-fix) | `0.0.0-dev` | `…/demo/0.0.0-dev` | generation-1 |
| **B** — after `marketplace update` + `plugin update` | `fedc656ce6f5` | `…/demo/fedc656ce6f5` | **generation-2** |
| **C** — a further commit, updated again | `6245ba0a3c94` | `…/demo/6245ba0a3c94` | **generation-3** |

The CLI said it plainly at stage B:

```
✔ Plugin "demo" updated from 0.0.0-dev to fedc656ce6f5 … Restart to apply changes.
```

**Stage C is the one that could have been missed.** "Delivers once" would satisfy a naive check —
the migration itself always looks like progress because the version string changes exactly once, from
the constant to a SHA. Stage C proves the *steady state* works too: a second commit produced a second
delivery. Without it, "the fix delivers" could have been literally true and useless.

### Two costs this run also measured

- **The orphaned cache directory is real.** `…/cache/mig/demo/0.0.0-dev` **survives** the migration
  and is never collected — the same class as the ~9.6 MiB orphan in §1.6/2B.6 and the 374 MiB
  `soleur.bak` in the issue. It belongs in the ADR's consequences, not discovered later.
- **The restart requirement is in the CLI's own output**, not folklore. Documented in the runbook and
  both READMEs.

### Where identity lands

`version` becomes a 12-character SHA prefix and `gitCommitSha` the full 40. Consistent with §1.9:
the key's absence is what makes the identity string *vary*, which is what the comparator reads.

---

## 1.4 — The `--url` install path, and a better legacy mitigation

**Run 2026-08-12. Two findings, one of which changes what the docs should recommend.**

### `claude plugin install --url …` does not exist

Both `README.md` and `plugins/soleur/README.md` documented it as an install path ("From GitHub
(without cloning)"). On CLI **2.1.227** it fails immediately:

```
error: unknown option '--url'
```

`claude plugin install --help` lists exactly three options — `--config`, `-h`, `-s/--scope`. So a
documented install path had been dead, silently, for an unknown period. Task 1.4 existed to probe
whether that path was *affected by the version-key deletion*; the answer is that the path does not
exist to be affected. Removed from both READMEs rather than corrected — `marketplace add` covers it.

### `marketplace add --sparse` fixes the legacy channel at the DEFAULT timeout

`claude plugin marketplace add` carries an undocumented-in-our-docs `--sparse <paths...>` flag
("Limit checkout to specific directories via git sparse-checkout (for monorepos)").

| Legacy `marketplace add jikig-ai/soleur` | Elapsed | Materialised |
|---|---|---|
| plain (§1.6/2B.6) | **329 s** — fails at the 120 s default | 342.7 MiB |
| `--sparse .claude-plugin plugins` | **78 s** — succeeds at the default | **16.98 MiB** |

`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` **unset** for the sparse run. 16.98 MiB is exactly the plain-git
floor recorded in the plan's `## Amendment 2026-08-12`, which is a good consistency check on both.

**This does not undo the decision.** The dedicated marketplace is still better for users — 13 s,
9.66 MiB (§2B), no flags to remember, and it is the channel the drift guard watches. But it does
change the *fallback*: anyone who must stay on the monorepo entry should use `--sparse` rather than
raising the timeout, because it works inside the CLI's own limit instead of arguing with it.

Docs and the recovery runbook updated to lead with `--sparse`; the timeout raise is demoted to the
already-destroyed-checkout case.
