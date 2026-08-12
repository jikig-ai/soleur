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
