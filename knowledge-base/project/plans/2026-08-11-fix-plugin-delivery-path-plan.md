---
title: "fix: merged plugin code now actually reaches installed users — SHA-tracked updates and a marketplace that installs in seconds, not minutes"
date: 2026-08-11
slug: fix-plugin-delivery-path
branch: feat-one-shot-7471-plugin-delivery-path
issue: 7471
closes: 7471
type: bug
lane: cross-domain
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The merged plugin code does not reach an installed user by the documented path. Two
independent defects were measured on a real install. First, the plugin manifest carries a
constant version string, so the updater's version comparison short-circuits and reports the
install as current while leaving a months-stale cache in place. Second, refreshing the
marketplace clones the whole monorepo, which exceeds the updater's default git timeout on a
repository this size; the refresh then leaves the local checkout in an unusable state.

This plan addresses delivery only. The underlying lock/lease library fix is correct and is
not in scope.

## Amendment 2026-08-12 — UC-1 resolved as outcome (b)

The operator resolved **UC-1** in
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/decision-challenges.md`:
ship the additive marketplace source in this PR. The deferral of option F is withdrawn. That
file's **RESOLVED** status block is the single record of the decision and its five consequences;
it is cited here by content anchor and **not duplicated** — read it there.

This section is the one place the amendment's own reasoning is written. Everything below
references it rather than restating it.

### The measured floor (new, and it belongs here before anything is built on it)

The challenge's premise — that a narrowed source avoids the whole-repo clone — was never
measured. It still is not measured *for the CLI*, which is what Phase 0.0 exists to do. What
**is** now measured is the **floor**: what git itself transfers when asked for the subtree only.
Run 2026-08-12 against `https://github.com/jikig-ai/soleur.git`:

```
git clone --filter=blob:none --depth=1 --no-checkout --sparse <url> s
cd s && git sparse-checkout set plugins/soleur && git checkout
```

| Quantity | Measured |
|---|---|
| `.git` after partial+shallow clone, no checkout | 794,973 B (0.76 MiB) |
| `.git` after the sparse checkout resolves | 7,454,753 B (7.11 MiB) |
| Working tree (`plugins/soleur` only) | 10,093,006 B (9.63 MiB), 914 files |
| **Total on disk** | **17,803,760 B (16.98 MiB)** |
| Today's full clone, for contrast | 215.4 MiB tree + 181.37 MiB packed history |

**This is a floor, not a prediction.** It proves the technique is possible with plain git and
sets the pass/fail band for Phase 0.0. It says nothing about whether Claude Code's `git-subdir`
implementation uses it — that is precisely the unmeasured premise, and Phase 0.0 measures the
CLI, not git.

### Correction: "~50 KB" describes the marketplace repo, not the delivered payload

UC-1 and the CTO framing both use "~50 KB". That figure is correct for the **marketplace source
repo** (a `marketplace.json`, a README, a licence — the thing `claude plugin marketplace add`
clones). It is **not** the delivered payload. The plugin itself is still materialised through the
`git-subdir` entry, and the floor above puts that at ~17 MiB, not 50 KB. Both numbers are used
below with the distinction kept explicit, because a compliance claim resting on a 340× wrong
number would not survive contact.

The minimisation conclusion is unaffected: everything the Art. 5(1)(c) / Art. 25(2) finding
named — `knowledge-base/legal/` (the Art. 30 register, 41 counsel-review memoranda), 333 design
screenshots, `knowledge-base/project/` — lies outside `plugins/soleur` and is not in the ~17 MiB.

### `closes: 7471` — why the frontmatter flipped, and the condition on it

The frontmatter was `refs: 7471`. The recorded reason (Plan Review, correctness panel item 1) was
that this PR bought P2 and P3 but not P1, because P1 needs a marketplace refresh to complete and
P5 was deferred. **Outcome (b) removes that gap**, and it removes it for the existing install too,
which is the part that had to be checked honestly rather than assumed:

- **New installs** follow a documented path that clones ~50 KB of marketplace and materialises
  ~17 MiB of plugin. P1 and P5b both land.
- **The one existing install** (alpha tester #1, `scope: project`) is on `soleur@soleur` and does
  **not** auto-migrate. Its route is `marketplace add <new source>` → `install soleur@<new
  marketplace> --scope project` → remove the old entry. The decisive point: **none of those steps
  clones 181 MiB.** The migration route no longer passes through the operation that times out,
  which is exactly what made the old `remove → re-add → reinstall` unusable. It is a documented,
  fast, in-default-timeout sequence for a population of one, carried by AC25's outbound.

So the PR does deliver the user-visible fix, and `closes:` is honest. **The flip is conditional
on Phase 0.0 passing.** If the falsification gate fires, outcome (b) does not resolve defect 2,
the run halts (Phase 0.8), and reverting the frontmatter to `refs: 7471` is an explicit item of
that halt branch — not something to be discovered at merge time.

## Deepen-Plan Gate Results

Run 2026-08-11 against the post-plan-review plan.

| Gate | Result |
|---|---|
| **4.5** Network-outage deep-dive (fired on `timeout`) | **PASS** — `## Hypotheses` answers all four layers with artifacts; L3/L7 opt-outs cite the successful raised-timeout clone as the discriminator |
| **4.6** User-Brand Impact halt | **PASS** — section present, non-placeholder, threshold `single-user incident` |
| **4.7** Observability gate | **PASS** — all five fields present and non-empty; `discoverability_test.command` first token `jq` (allowlisted), zero `ssh` matches |
| **4.8** PAT-shaped variable halt | **PASS** — no matches |
| **4.9** UI-wireframe artifact halt | **TRIGGERS — determination below, not a silent pass** |
| **4.10** Encryption Posture halt | **PASS** — section present; no `plaintext-exception`, no `cert_verification: off`, so no `exception` block required |

### Gate 4.9 — explicit determination (flagged for overturn, not resolved by fiat)

The gate fires: `## Files to Edit` contains `plugins/soleur/docs/pages/getting-started.njk` and
`changelog.njk`, the glob superset matches `**/*.{njk,…}`, and zero committed `.pen` files are
referenced. By the letter of the glob rule this is a HALT.

**Two authorities in the same document disagree.**
`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` states under **Excluded (no
wireframe required)**: *"Pure copy or style tweaks with no structural/layout change"*. Its glob
superset states the opposite precedence: *"Any match forces the UI-surface determination true
regardless of subjective assessment."*

**Determination: the Excluded clause governs here, and the reason is not subjective.** The two
edits change (a) the text inside one `<pre><code>` block and (b) the wording of one FAQ answer
plus its JSON-LD twin. No page, route, component, modal, banner, nav, layout, flow, or template
*structure* changes; nothing new renders; no user journey gains a step. The glob's "regardless of
subjective assessment" clause exists to stop a judgement call from excusing a real UI surface —
it is not aimed at a categorical carve-out the same document grants.

**Operator determination 2026-08-11: the advisory determination is ACCEPTED.** No wireframe is
required for these two edits; the Excluded clause governs. This is a decision on these specific
copy-only edits, not a general licence for `.njk` changes to claim the carve-out — the standing
recommendation below (reconcile the two clauses in `ui-surface-terms.md`) still holds.

**This is recorded, not skipped.** `ux-design-lead` does **not** appear in `Skipped specialists:`
(the failure mode `wg-ui-feature-requires-pen-wireframe` exists to prevent); the Product/UX Gate
is declared **ADVISORY** with this reasoning in `## Domain Review`, and the gate ambiguity is
surfaced in the session summary. **If plan-review or the operator disagrees, the remedy is one
`ux-design-lead` invocation** — cheap, and preferable to a precedent that lets any `.njk` copy
fix claim the carve-out.

**Standing recommendation:** the glob superset and the Excluded clause should be reconciled in
`ui-surface-terms.md` itself, so the next plan touching a `.njk` string does not re-litigate this.
That is a workflow fix, not part of this change.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verified against | Verdict |
|---|---|---|
| Issue #7471 open, untargeted | `gh issue view 7471` — `state: OPEN`, label `type/bug`, no milestone | Holds |
| #7409 resolved by PR #7426 | `gh issue view 7409` — `state: CLOSED`, `closedByPullRequestsReferences: [7426]` | Holds; this plan is downstream of it |
| `plugins/soleur/plugin.json` carries the sentinel | Path does **not** exist. Manifest is `plugins/soleur/.claude-plugin/plugin.json` | **Stale path in the issue body.** Same file, wrong path. Every reference below uses the real one |
| "Publish a real version" is an unconsidered idea | `knowledge-base/project/brainstorms/2026-03-03-tag-only-versioning-brainstorm.md` rejected-options table; ADR-017 `## Decision` | **Stale.** Writing a version into the manifests from CI is the *exact* alternative ADR-017 rejected, and for a reason that still holds — see "The rejected-alternative trap" below |
| The lock/lease fix itself is correct | Out of scope by construction; ADR-178 is merged (`9b8cea08b`) | Holds |

**The rejected-alternative trap.** The 2026-03-03 brainstorm chose the sentinel because
`github-actions[bot]` is blocked from pushing to `main` by the **CLA Required** repository
ruleset. Every bypass was enumerated and rejected (GitHub App, PAT, disabling the ruleset,
`claude-code-action`, merge queues), and tag-only versioning was selected precisely to
"eliminate the push-to-main requirement entirely". A CI step that writes a computed version
back into the manifests re-creates that push. The constraint that killed it has not changed.

**The false premise, in one line.** That same brainstorm asserts: *"Claude Code does not use
this field for runtime behavior."* It does. That single unverified sentence is the root cause
of defect 1, and ADR-017 inherited it without re-checking.

### The measured control group (the finding that reshapes this plan)

`version` in `plugin.json` is **optional**. When it is absent from *both* the plugin manifest
and the marketplace entry, Claude Code falls back to tracking the plugin source's **git commit
SHA**. This is not read off documentation — it is measured on this machine, against the same
CLI, with a control group of six plugins whose source shape is structurally identical to
Soleur's (a `github` marketplace source, plugin entries with relative `./plugins/<name>`
paths):

```
$ jq 'has("version")' ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/pr-review-toolkit/.claude-plugin/plugin.json
false                                   # keys are ["author","description","name"] — no version key at all
```

```
$ jq '.plugins["pr-review-toolkit@claude-plugins-official"]' ~/.claude/plugins/installed_plugins.json
{ "version": "unknown",
  "installPath": ".../cache/claude-plugins-official/pr-review-toolkit/unknown",
  "lastUpdated": "2026-08-11T16:50:07.368Z",
  "gitCommitSha": "20a5a1f1a2b55b13e85dff5416613a796d089016" }
```

Six plugins (`pr-review-toolkit`, `feature-dev`, `commit-commands`, `frontend-design`,
`github`, `playwright`) share that `gitCommitSha` and all carry today's `lastUpdated`. They
**received updates** while their version string stayed the constant `"unknown"`. Two further
properties fall out of the same reading:

- The cache directory component stays `unknown` and is refreshed **in place** — so this route
  does not accumulate a directory per release. **[Corrected by CTO review:** #71074 does not
  bite in *steady state*, but it does bite **once, per existing install, at migration**: the
  `installed_plugins.json` entry's `installPath` is rewritten from `.../0.0.0-dev` to
  `.../unknown` and the old ~9.5 MiB directory is orphaned permanently. Record the one-time
  orphan; do not claim zero.**]**
- **The migration self-delivers, exactly once.** The recorded version is `0.0.0-dev` and the
  post-change manifest yields `unknown`. Those strings are unequal, so the *first*
  `plugin update` after the new manifest lands actually fires — the version comparator delivers
  its own replacement, and every subsequent update rides the SHA.
- A versioned plugin already carries a `gitCommitSha` too (`warp@claude-code-warp` = `2.2.0` +
  `e0e18e16`; `soleur@soleur` = `0.0.0-dev` + `98ad03a`). The SHA is recorded either way; only
  the *comparison* differs. This is a comparator switch, not a new tracking mechanism.
- **The CLI has at least three undocumented recording modes**, none contracted:
  version-with-SHA (above), keyless-with-SHA (the control group), and
  `code-review@claude-plugins-official` = `version: "15b07b46dab3"` with **no** `gitCommitSha`.
  Upstream #79950 is actively going to change this comparator. Rollback is cheap and must be
  stated: re-add the key.
- `version` is tracked separately from `gitCommitSha` in `installed_plugins.json`, which is
  why the SHA can advance while the path component does not.

Contrast the two entries that *do* pin a version: `security-guidance/2.0.6` and
`supabase/0.1.12` **and** `supabase/0.1.13` — the versioned route is exactly the one that
leaves stale directories behind.

### Upstream defect corpus (`anthropics/claude-code`)

Defect 1 and defect 2 are both already filed upstream. Neither is fixable in this repository.

| Issue | State | Relevance |
|---|---|---|
| **#79950** | OPEN (2026-08-07) | *"`claude plugin update` reports 'already at the latest version' … when a marketplace's declared version string doesn't change, even though real commits landed"* — defect 1 verbatim |
| **#77927** | OPEN | Desktop GUI uses a ~60s clone timeout vs the CLI's 120s; documents `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` default as 120000 ms |
| **#76882** | OPEN | Marketplace update fetches new code but does not update `installed_plugins.json` |
| **#83777** | OPEN | Writes metadata without refreshing the marketplace source |
| **#80367** | OPEN | Staging clones under `cache/temp_*` never reclaimed (1318 dirs / ~8 GB in 8 days) |
| **#71074** | OPEN | Plugin cache accumulates old version directories; no pruning |

`claude plugin update --help` on the installed CLI offers exactly one flag, `--scope`. There is
**no `--force` / `--reinstall`**; the only forced refresh is uninstall + reinstall.

### Measured repository size — why the refresh times out

Measured in this worktree, not estimated:

| Quantity | Value |
|---|---|
| Tracked files at HEAD | 13,523 |
| HEAD tree, blob bytes | 215.4 MiB |
| Packed history (`size-pack`) | 181.37 MiB |
| `plugins/soleur` subtree | **9.5 MiB / 887 files — 4.4% of the checkout** |
| `knowledge-base/` | 171.85 MiB — **80% of the checkout** (`project/` 84.2, `product/` 77.7) |
| Anthropic's official marketplace checkout, for scale | 7.1 MB |

The marketplace clone moves ~215 MiB of tree plus ~181 MiB of history to deliver a 9.5 MiB
plugin. `~/.claude/plugins/marketplaces/soleur/` **does not exist on this machine right now** —
`known_marketplaces.json` still lists it (`autoUpdate: true`, `lastUpdated`
`2026-08-11T16:50:06Z`) pointing at a directory the failed refresh destroyed. The operator's
install is in the broken state as this plan is written.

### Relevant repo mechanisms and precedents

- `.github/workflows/version-bump-and-release.yml` → `.github/workflows/reusable-release.yml`
  (`component: plugin`, `tag_prefix: v`, `path_filter: plugins/soleur/`). The `Compute next
  version` step derives the version from git tags into `$GITHUB_OUTPUT` and **never writes a
  file**. Grepping the whole workflow for `plugin.json` / `marketplace.json` returns nothing.
  No workflow in the repo auto-commits a version.
- **`plugins/soleur/docs/_data/plugin.js:14` is a live consumer of the `version` key**:
  `if (data.version) plugin.version = data.version;`, feeding
  `plugins/soleur/docs/_includes/base.njk:96` → `"softwareVersion": {{ plugin.version | jsonLdSafe | safe }}`.
  Its release lookup is `docs/_data/github.js:59`
  (`releases[0]?.tag_name?.replace(/^v/, "") ?? null`) with a `SOLEUR_DOCS_OFFLINE=1` hatch that
  yields `version: null`.
  **[Corrected 2026-08-11 by CTO review — measured, and the earlier wording here was wrong.]**
  This does not degrade to "a wrong-but-present string". It **throws**. `jsonLdSafe`
  (`eleventy.config.js:30`) is `JSON.stringify(value).replace(/<\//g, …)`, and
  `JSON.stringify(undefined)` returns the *value* `undefined`, so `.replace` raises
  `TypeError: Cannot read properties of undefined (reading 'replace')` — verified by execution.
  `base.njk` is the base layout for **every page**, so the build dies on the first template.
  And `SOLEUR_DOCS_OFFLINE=1` is not a rare hatch: two CI suites spawn a full Eleventy build
  with it in `beforeAll` — `plugins/soleur/test/seo-aeo-drift-guard.test.ts:72` and
  `plugins/soleur/test/marketing-content-drift.test.ts:77`. **The manifest edit alone turns CI
  deterministically red**, while the production docs deploy stays green because a real release
  tag is present — the failure appears only on the hermetic path, which is the worst shape.
- **The sentinel has zero mechanical enforcement.** No test, lint, or CI step asserts the
  version value. It is prose in exactly four places: `AGENTS.rules.md`
  (`wg-never-bump-version-files-in-feature`), `plugins/soleur/AGENTS.md` pre-commit checklist,
  `plugins/soleur/skills/ship/SKILL.md` "Never edit version fields", and `CONTRIBUTING.md`
  "Plugin changes". `marketplace.json` has no test asserting on it at all.
- **`--check` is this repo's established shape** for committed content that must track computed
  truth: `scripts/sync-readme-counts.sh --check` (wired at `.github/workflows/ci.yml:47`) and
  `plugins/soleur/scripts/sync-grok-agent-compat.ts --check` (gated by
  `plugins/soleur/test/grok-inspect-contract.test.ts`, the one precedent for CI-enforced
  `.claude-plugin/` content). Both fail the build; neither writes back.
- **`scripts/prod-version-drift-check.sh`** (#7091) is the repo's staleness-detector precedent:
  a range query (`git log --first-parent <sha>..origin/main -- <pathspec>`), a four-verdict
  table (`CLEAN` / `DRIFT_PENDING` / `DRIFT_SUSTAINED` / `CHECK_ERROR`), and the stated rule
  *"'we could not evaluate' must NEVER be encoded as 'no drift'"*. Its `PATHSPEC` already
  includes `plugins/soleur/`, but it measures the web-platform container, never a user's cache.
- **No mechanism anywhere verifies an installed plugin cache against the repo.** The
  `SessionStart` hook in `plugins/soleur/hooks/hooks.json` is `welcome-hook.sh`, a first-run
  sentinel that early-exits unless `plugins/soleur` exists in the project root — so it never
  fires for an installed user, and it compares nothing.
- **Schema precedent for a narrowed source** is live in Anthropic's own marketplace: third-party
  entries use `{"source": "git-subdir", "url": …, "path": "plugins/…", "ref": "v1.5.5", "sha": …}`
  (42crunch, adobe), documented as cloning *sparsely* to minimise bandwidth for monorepos.

### Institutional learnings

- `knowledge-base/project/learnings/2026-03-03-serialize-version-bumps-to-merge-time.md` — the
  CLA-ruleset constraint behind tag-only versioning; `gh release create` tags without pushing.
- `knowledge-base/project/learnings/build-errors/2026-05-19-tag-glob-collision-blocks-plugin-release.md`
  — the anchored-regex tag post-filter now in `reusable-release.yml`; relevant only if the
  release path is touched.
- `knowledge-base/project/learnings/2026-03-19-git-tag-sort-shallow-clone-semver.md` — shallow
  clones blind `--sort=version:refname`. A caution against any "just make it shallow" instinct
  applied to the *release* checkout (it does not apply to the marketplace clone, which the CLI
  owns).
- ADR-178 `## Consequences` already states this defect and its measurement (64 skills vs 96,
  mtime 2026-05-10) under the heading *"Delivery is not guaranteed by merging"*, and the
  archived #7409 plan made it an explicit step: *"A fix nobody receives is not a fix."* The
  question has been asked and recorded as a limit twice; this plan is the first to close it.

### Property List (Phase 0.6b)

- **P1** — An installed user who runs the documented upgrade path ends up running the current
  plugin code.
- **P2** — When plugin code changes on `main`, the value the updater compares changes too.
- **P3** — The operator is never told "already at the latest version" while the cache is stale.
- **P4** — A failed marketplace refresh leaves the previously working checkout intact.
- **P5a** — A marketplace refresh **completes at all**, by whatever means.
- **P5b** — A marketplace refresh completes inside the CLI's **default** git-clone timeout.
- **P6** — From a destroyed checkout, there is a documented route back to a working install.

**[Revised under plan review — the original list had a logic defect.]** P5 was originally one
property worded "completes inside the CLI's default timeout", and option E (raising
`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS`) was marked as buying it "partially". That is unearned by
construction: raising the timeout is precisely *not* completing within the default. Splitting
P5a from P5b makes the accounting honest — **E buys P5a and buys nothing of P5b; only option F
buys P5b.** P6 was missing entirely, which left Phase 3.2's recovery sequence — the single most
user-valuable deliverable after the deletion, and the only thing that helps the one currently
broken install — formally unjustified while the C4 work sat at the same justification level.

### Cut List (Phase 0.6b) — cut before research, not after

| Mechanism the ask proposed | Property it buys | Why it is cut |
|---|---|---|
| CI writes the computed version into `plugin.json` + `marketplace.json` and pushes to `main` | P2 | Omitting the key buys P2 already (measured control group above). The write-back additionally needs a bot push to `main` that the CLA ruleset blocks — the precise constraint ADR-017 was created to avoid — re-triggers `version-bump-and-release.yml` through its own `paths: ['plugins/soleur/**']` filter, and leaves one un-GC'd cache directory per release (#71074) |
| Make the updater compare a content hash / commit SHA | P2 | Not implementable here — CLI internal. And unnecessary: it is *already what the CLI does* when `version` is absent. Satisfied by configuration, not by an upstream change |
| Ship a shallow / partial clone for marketplace refresh | P5 | Not implementable here — CLI internal (upstream #77927). Soleur's only levers are *what* is cloned and documenting the env var |
| Raise the default clone timeout | P5 | Not implementable here — CLI internal |
| Restore the `.bak` on refresh failure | P4 | Not implementable here — CLI internal. Track upstream |
| A Soleur-side `.bak`-restore / marketplace-repair script | P4 | **Cut, then partially re-opened — see below.** The original reasoning was that P4's *occurrence* is gated on P5, so once refresh fits the timeout the destructive arm is not reached |
| Shrink the monorepo (prune `knowledge-base/`) | P5 | Measured: `knowledge-base/` is 80% of the HEAD tree, but the 181 MiB *history* pack is transferred by a full clone regardless, so deleting files today does not shrink what is cloned. Not a fix — a separate long-horizon track, recorded as a Non-Goal |

### Cut-List correction (raised by CPO review — a self-contradiction in the row above)

The P4 row cut the repair mechanism **because P5 would remove the failure**, and the plan then
**deferred P5**. The cut's own escape clause — *"re-open only if the chosen P5 option does not
land the refresh inside the default timeout"* — therefore fires: with P5 deferred, P4 is left
both ungated and unrepaired. Two measured facts sharpen it:

- `known_marketplaces.json` records `"autoUpdate": true` on the `soleur` entry and on **none**
  of the other three marketplaces on this machine. The destructive arm is reachable with **zero
  user action**.
- The checkout is already destroyed: `~/.claude/plugins/marketplaces/soleur/` is absent while a
  `soleur.bak/` from 2026-08-11 18:02 remains, and `known_marketplaces.json` still points at
  the absent path.

**Resolution.** The *code* half of the repair stays cut — restoring a `.bak` is CLI-internal and
cannot be implemented here. The *recovery* half is re-opened and promoted out of "troubleshooting"
into Phase 3's critical path, because for the only currently-installed user it is not a
nice-to-have but the sole route back to a working install. The `autoUpdate` exposure is recorded
and its refresh cadence is a Phase 0 measurement, not an inference from timestamps.

**Still stands after the UC-1 resolution, and it is worth saying why.** The escape clause fired
because P5 was deferred; P5 is now undeferred, which might look like grounds to re-cut P4. It is
not. `jikig-ai/soleur` is **retained** with `autoUpdate: true`, so the destructive arm remains
reachable with zero user action for anyone on the old entry — and that includes the one existing
install until it migrates. P4's exposure is narrowed to the old path, not removed. The recovery
half stays in Phase 3.

### The delivery paradox (raised by CPO review — the structural finding)

**The fix for defect 1 ships inside the manifest, and seeing the new manifest requires a
marketplace refresh — which is defect 2.** The fix cannot self-deliver by the path it fixes. For
the current install it is worse than gated: the checkout is already gone, so the only route is
remove → re-add → reinstall, and the re-add *is* the 120s clone. This is why Phase 3 is not
optional garnish on Phase 1.

**Broken by the UC-1 resolution — this is the structural argument for outcome (b), stated once.**
The paradox holds only while there is a single delivery path. Phase 1B adds a second one, and the
new one is not the broken one: `marketplace add <new source>` clones ~50 KB and does not pass
through the 181 MiB operation at all. So the fix now has a route to a user that does not depend on
the defect it fixes. That is the difference between a fix and a fix that arrives, and it is why
the challenge treated the deferral as load-bearing rather than a matter of scope taste.

### Population calibration

`knowledge-base/product/roadmap.md` line 81: **Beta users: 1** — alpha tester #1 (Skouer),
onboarded 2026-08-06 **on the self-hosted CLI plugin**. The affected population and the total
population are the same set, which is what makes `single-user incident` the literal, not
rhetorical, threshold. It also relocated the real deadline: the deferred P5 fix would have become
cohort-wide the moment #1439 (recruit 10 founders) resumed — a roadmap dependency recorded
nowhere. **Under the UC-1 resolution that deadline is met in advance:** P5b lands in this PR, so
the cohort arrives onto the narrow path rather than onto the one that times out. The #1439
relationship is no longer a blocking dependency, and Phase 3.4 keeps one line of it in the PR
body so a future reader of #1439 can see the ordering was deliberate.

### Value-Proposition Measurement (Phase 0.6c)

The plan's saving is a **delivery** property, not a cost saving, so no fan-out budget applies.
The one quantified claim is the size ratio above, produced by
`git ls-tree -r HEAD --long [-- plugins/soleur] | awk '{s+=$4}'` and `git count-objects -vH` in
this worktree. A prior research pass reported "2,216 tracked files / 362M .git" from the bare
root; the worktree figures (13,523 files, 181.37 MiB pack) are the ones used throughout,
because they describe the tree a marketplace clone actually materialises.

### CLI-verification gate

Every CLI invocation this plan puts near user-facing docs was run against the installed CLI on
2026-08-11: `claude plugin --help`, `claude plugin update --help` (flags: `-h`, `--scope` only).
`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` is confirmed as milliseconds, default `120000`, surfaced by
the CLI's own error text. Marketplace/plugin source schemas are from
`https://code.claude.com/docs/en/plugin-marketplaces.md` and
`https://code.claude.com/docs/en/plugins-reference.md#version-management`, cross-checked against
the live `claude-plugins-official` marketplace manifest on this machine.

### Skill description budget

No `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate in this change. Check
skipped (Phase 1.8).

### Lane

No `knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/spec.md` exists, so
there is no `lane:` to carry forward. Defaulted to `cross-domain` (TR2 fail-closed).

## Research Reconciliation — Issue Body vs. Codebase

| Issue-body claim | Reality | Plan response |
|---|---|---|
| The sentinel lives at `plugins/soleur/plugin.json` | The manifest is `plugins/soleur/.claude-plugin/plugin.json`; there is no file at the cited path | Use the real path everywhere. The sibling `.claude-plugin/marketplace.json` carries a second copy of the same sentinel, which the issue does not mention |
| "Publish a real version so the updater stops short-circuiting on a constant string" | Correct diagnosis, but the implied mechanism (CI writes a version into the manifests) is the alternative ADR-017 rejected, blocked by the CLA ruleset on `github-actions[bot]` pushes | Keep the diagnosis, replace the mechanism: **delete** the key so the CLI falls back to the commit SHA. Strictly cheaper and preserves ADR-017's "no version in files" posture |
| "Make marketplace refresh viable … (shallow/partial clone or a raised timeout default)" | Both are Claude Code CLI internals. Nothing in this repository selects the clone strategy or the timeout default | Re-scope to the two levers that are ours: *what* gets cloned and *what the documented command says* — **both now in scope.** The first was deferred and is undeferred by the UC-1 resolution: Phase 1B narrows the clone to `plugins/soleur` via a `git-subdir` marketplace source, gated on Phase 0.0. Record the clone-strategy and timeout-default internals as upstream |
| "Make refresh failure restore the `.bak` rather than destroy the checkout" | Entirely CLI-internal | Out of scope by capability, not by choice. Tracked upstream; stated plainly rather than assumed away |
| `0.0.0-dev` is enforced somewhere | Zero tests, zero lint rules, zero CI steps assert it. Four prose sites only | The blast radius of removing it is governance prose plus one docs-data consumer — not a mechanical failure surface |

## Hypotheses

Phase 1.4 fired on `timeout` in the issue description. The checklist's L3→L7 ordering applies,
and the issue itself contains the confound it exists to catch: GitHub SSH was down during the
measurement window. Each layer is answered with an artifact, not with "obvious".

1. **L3 — network/transport outage (the confound).** *Refuted, with an artifact.* The
   operator's recovery run over the **same** network, with the **same** `url.insteadOf` HTTPS
   rewrite in place, succeeded once `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=900000` was set
   (`entries=43 head=9b8cea0`). A transport-layer outage does not become healthy because a
   client-side deadline was raised; a duration problem does. This is the discriminator, and it
   is the operator's own captured output — not an inference.
2. **L3 — DNS / routing.** *Opted out, per the checklist's opt-out clause.* Same session, same
   host, same resolver: the raised-timeout clone reached `github.com` and completed. A route
   that resolves and transfers 181 MiB is a verified route.
3. **L7 — TLS / proxy.** *Opted out.* The successful clone completed a full TLS session to
   GitHub over the HTTPS rewrite. Nothing intermediary is implicated.
4. **L7 — application layer (the real hypothesis).** **Confirmed by measurement.** The clone is
   a full deep clone of a repository whose HEAD tree is 215.4 MiB across 13,523 files with
   181.37 MiB of packed history, performed to deliver a 9.5 MiB plugin (4.4% of the tree).
   Anthropic's own marketplace checkout, for scale, is 7.1 MB. The 120,000 ms default is not
   generous or mean; this repository is roughly thirty times the size the default was sized for.
5. **Defect 1 is not a network hypothesis at all** and is not subject to this ordering. It was
   measured *after a successful refresh*: the marketplace checkout held the merge commit while
   the installed cache held code from 2026-05-10. Both halves of the comparison were on local
   disk.

## Alternatives Considered

| Option | Buys | Verdict |
|---|---|---|
| **A. Delete the `version` key from both manifests** | P1, P2, P3 | **Selected.** Two deletions. Measured against a six-plugin control group with an identical source shape. Preserves ADR-017's intent (no version lives in a committed file) more faithfully than the sentinel did |
| B. CI writes the computed version into the manifests and pushes to `main` | P2 | **Rejected.** Requires the bot push to `main` that the CLA Required ruleset blocks — the exact constraint that produced ADR-017. Also self-triggers `version-bump-and-release.yml` via its own `paths` filter, and strands one un-GC'd cache directory per release (#71074) |
| C. Set the version to the commit SHA at build time | P2 | **Rejected.** Same push-to-`main` problem as B, plus it re-introduces a version string the CLI would key the cache directory on — the directory-proliferation failure that route A avoids entirely |
| D. A Soleur-side staleness detector (SessionStart hook comparing the installed cache against `origin/main`) | P3, partially | **Rejected for this PR, worth revisiting.** It buys a property A already buys for the *update* path, and only adds value for the case where the *marketplace refresh* silently failed. That case disappears if the deferred P5 fix lands. Building it now is machinery ahead of the need — and `plugins/soleur/hooks/welcome-hook.sh` would have to stop early-exiting outside this repo, a change with its own blast radius. If it is ever built, mirror `scripts/prod-version-drift-check.sh`'s four-verdict shape, never a boolean |
| **E. A persistent timeout env setting, documented on the surfaces users actually read** | P5a | **Selected — re-scoped three times.** *(Third re-scope, UC-1 resolution:* with F selected, E is no longer the delivery mechanism for the fix. It is retained because `jikig-ai/soleur` **stays** a valid marketplace carrying `autoUpdate: true`, so the 181 MiB refresh remains reachable for anyone still on the old entry — including the one existing install until it migrates, and the four CI surfaces in Phase 0.9. E covers that residue; it is no longer the headline.)* Prior wording, unchanged: **selected as a stopgap — re-scoped twice under review.** Originally "fold the var into the documented one-liner (README only)". CTO: a command prefix sets the var for *one invocation*, but `autoUpdate: true` fires the refresh inside ordinary sessions, so the automatic, higher-frequency, user-invisible arm stays at 120s. It must be a **persistent** setting (an `env` block in `~/.claude/settings.json`, or a shell-profile export), and that route must be verified before it is documented. CPO: README is not where users go — the docs site is |
| **F. Publish a small dedicated marketplace source, additive, whose single entry is a `git-subdir` into `jikig-ai/soleur`** | P1, P5a, **P5b** | **Selected — the deferral is withdrawn.** UC-1 was resolved as outcome (b); see the RESOLVED block in `decision-challenges.md` for the decision and its five consequences, and `## Amendment 2026-08-12` above for this plan's reasoning. The schema is proven (Anthropic's own marketplace uses `git-subdir` + pinned `ref`/`sha` for 42crunch and adobe). The shape is **additive**: a *second* repo (~50 KB) alongside `jikig-ai/soleur`, which remains a valid marketplace, so no existing install breaks. Cost: one new repo, a plugin-ID change for new installs, and a sweep of four live `soleur@soleur` consumers (Phase 0.9). **The epistemic objection is preserved, not waived** — the premise that `git-subdir` avoids the full clone is still doc-sourced. It is no longer deferred to a follow-up issue; it is **Phase 0.0, at the front of the plan, with a numeric halt.** Option F is the *only* option that buys P5b, which is why the plan is willing to gate itself on measuring it rather than drop it |
| G. Point the *marketplace* source at a subdirectory of this repo | P5 | **Refuted by the schema.** Marketplace sources are github / git URL / local path / remote JSON URL. `git-subdir` is a *plugin* source, read only after the marketplace clone has already completed. Recorded so it is not re-proposed. **This is precisely why F needs a second repo rather than a path inside this one** — the marketplace clone happens first, so the only way to make it small is to point it at something small |
| H. Shrink the repository | P5b | **Rejected as a fix.** 80% of the HEAD tree is `knowledge-base/`, but a full clone transfers the 181 MiB history regardless, so deleting files today changes nothing about what is cloned. A separate long-horizon track |
| **I. Set `autoUpdate: false` on the `soleur` marketplace entry** | P4 | **Added under plan review — this was a real gap, not a rejected option.** The plan measured that `autoUpdate: true` is what makes the destructive refresh reachable with zero user action, then proposed a *timeout* variable, which does not disable the automatic operation. Turning auto-refresh off removes the automatic destructive arm outright and costs nothing. Measured limit: `claude plugin marketplace --help` exposes only `add`/`list`/`remove`/`update` — **no flag sets `autoUpdate`**, so this is a `known_marketplaces.json` edit, and whether that survives the CLI rewriting the file is unmeasured. Phase 3.1 measures it; if it holds, it is strictly better than the env var for P4 and they are complementary, not alternatives |

## User-Brand Impact

**If this lands broken, the user experiences:** `claude plugin update soleur@soleur` printing a
green checkmark and exiting 0 while their `~/.claude/plugins/cache/soleur/soleur/` keeps running
months-old skills — the failure mode the issue names as "the worst shape of failure, because it
is indistinguishable from success". Concretely, that has already happened: the lock/lease layer
merged for #7409 reached no installed user, so worktree reaping has been running without its
concurrency guard on every install.

**If this leaks, the user's workflow is exposed via:** no new exposure vector is opened. The
existing one is worth naming because this plan touches it — the marketplace clone delivers the
entire public monorepo to every installer, including `knowledge-base/project/` (84 MiB of
plans, specs and session learnings) and `knowledge-base/product/` (78 MiB, largely design
screenshots). The repository is already public, so this is a distribution-mechanism
observation, not a disclosure. **Option F, now in scope (Phase 1B), narrows the new-install
payload to `plugins/soleur/` — measured floor ~17 MiB, see `## Amendment 2026-08-12`.** It does
not narrow it for anyone still installing from the old marketplace entry, which stays valid.

**Brand-survival threshold:** `single-user incident`.

Every installed user is affected simultaneously and silently, and the surface is the one a
non-technical founder is told to trust. `requires_cpo_signoff: true` is set in the frontmatter;
`user-impact-reviewer` runs at review time per `plugins/soleur/skills/review/SKILL.md`.

## Non-Goals

- Fixing the Claude Code CLI's destructive marketplace-refresh failure, its clone strategy, or
  its default timeout. Not implementable in this repository (upstream #79950, #77927, #76882,
  #83777, #80367, #71074).
- Changing how releases are versioned. Git tags remain the single source of truth; this plan
  removes the vestigial file-side copy rather than replacing it.
- Reducing repository size. Measured as ineffective against a full clone (option H).
- ~~Publishing a dedicated marketplace source (option F)~~ — **no longer a Non-Goal.** UC-1 was
  resolved as outcome (b) and option F is now in scope as Phase 1B. What remains out of scope,
  and is stated here so the boundary is not assumed away:
  - **Retiring or redirecting `jikig-ai/soleur` as a marketplace.** It stays valid and keeps
    serving existing installs. Deprecating it is a separate decision with its own migration
    window.
  - **Automatically migrating existing installs** to the new plugin ID. There is no CLI
    mechanism for it, and at a population of one the route is documented plus AC25's outbound.
  - **Migrating the four CI/scheduled-workflow `soleur@soleur` consumers** in the same PR —
    Phase 0.9 sweeps and *decides* for each; moving them is only in scope where the decision is
    to move them, and any that stay are recorded with the reason.
- Building the operator-side delivery canary — real work with its own failure modes and an
  auth-feasibility gate; tracked separately (Phase 3.5).
- Building an in-session staleness banner (option D) — deferred, trigger named.
- Rewriting the remaining install-command surfaces (`claude-code-plugins.njk`,
  `ai-agents-for-solo-founders.njk`, the blog posts,
  `knowledge-base/marketing/distribution-content/soleur-vs-crewai.md`). Those state
  `claude plugin install soleur`, which is not the failing verb; the two surfaces this plan
  edits are the ones carrying the *marketplace add* command and the false *upgrade* claim.
  **Re-examined under the UC-1 resolution and deliberately kept as a Non-Goal.** The old
  reasoning — "if option F lands they all change together" — expired the moment F moved into this
  PR, so it cannot carry the deferral any more. The deferral survives on a different and better
  reason: `claude plugin install soleur` is **still accurate** after Phase 1B, because
  `jikig-ai/soleur` remains a valid marketplace. Nothing on those surfaces becomes false. They
  become *not-the-recommended-path*, which is a marketing refresh, not a correctness fix, and it
  belongs with the old-marketplace-deprecation issue. Adding a fourth and fifth surface to this
  PR would also cut against the standing review finding that three stopgap surfaces is already
  one too many at a population of one.

## Implementation Phases

### Phase 0 — Falsify the plan before building on it

The plan now rests on **two** claims, and both are falsifiable here. Claim one: a keyless
manifest makes the CLI track the commit SHA (measured against a control group, never against
*Soleur's own* install). Claim two, added by the UC-1 resolution and **never measured at all**:
that a `git-subdir` marketplace entry avoids cloning the whole repository. Claim two runs first,
because everything the resolution added is built on it.

#### 0.0 — Falsification gate: does `git-subdir` actually avoid the full clone?

**This is the first task in the plan. Nothing in Phase 1B is built before it returns a number.**

Option F is the only option that buys P5b, and its premise is sourced from one sentence of
Anthropic's documentation ("clones sparsely to minimise bandwidth for monorepos") and nothing
else. It was task 1 of the follow-up issue that outcome (b) dissolved; dissolving the issue does
not dissolve the measurement.

**Setup.** Build a throwaway marketplace source — a directory (or a scratch repo) containing only
a `.claude-plugin/marketplace.json` whose single plugin entry is:

```json
{ "name": "soleur", "source": { "source": "git-subdir",
  "url": "https://github.com/jikig-ai/soleur.git", "path": "plugins/soleur" } }
```

**The measurement.** With a clean `HOME` (`HOME=$(mktemp -d)`), so nothing pre-existing is
counted:

```
/usr/bin/time -v claude plugin marketplace add <scratch-source> \
  && /usr/bin/time -v claude plugin install soleur@<scratch-name> --scope project
du -sb "$HOME/.claude/plugins/marketplaces" "$HOME/.claude/plugins/cache"
```

**The number that falsifies it.** Sum the two `du -sb` byte counts.

| Total materialised bytes | Verdict |
|---|---|
| **< 50 MiB (52,428,800 B)** | **PASS.** Comfortably above the 16.98 MiB floor measured in `## Amendment 2026-08-12`, comfortably below the 181.37 MiB pack. The premise holds |
| **≥ 50 MiB** | **FALSIFIED.** The CLI is fetching materially more than the subtree. Do not attempt to explain the middle of the band away — the gate is fail-closed |

**Second clause, and it is not optional.** The whole point of F is P5b — completing inside the
CLI's *default* timeout. Run the measurement with `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` **unset**.
If either command dies on the 120,000 ms default, F buys P5a at best and the gate fails on that
clause alone, whatever the byte count says.

**On failure, the run STOPS.** It does not fall back, re-scope, or proceed with a narrowed
version of Phase 1B. Outcome (b) does not resolve defect 2, which is the ground the operator's
decision stood on, so the decision needs re-taking with the measurement in hand — see the halt
table at 0.8. Building Phases 1B, 2 and 4 on a refuted premise is the exact failure the
challenge existed to prevent.

**Diagnostic, not a substitute.** If the gate fails, also record whether the CLI's git invocation
used `--filter` / `--sparse` at all (`GIT_TRACE=1`). The floor measurement proves plain git can do
this in 17 MiB; a failure therefore locates the defect in the CLI, which makes it an upstream
report alongside #77927 rather than a mystery.

0.1 Re-verify the control group is still what it was, and record the reading:
`jq 'has("version")' ~/.claude/plugins/marketplaces/claude-plugins-official/plugins/pr-review-toolkit/.claude-plugin/plugin.json`
must print `false`, and the matching `installed_plugins.json` entry must carry a `gitCommitSha`.

0.2 Build a keyless-manifest fixture and confirm the CLI's behaviour end to end against a
Soleur-shaped source *before* touching the real manifests. A local-path marketplace whose
`plugins[0]` entry and `plugin.json` both omit `version` is enough; the observable is that a
`gitCommitSha` is recorded and that a second commit changes it.

0.3 Record what the cache path becomes. If it is `unknown`, note that the migration leaves the
old `0.0.0-dev/` directory behind, orphaned and never GC'd (#71074) — that is a real cost of
option A and belongs in the ADR's consequences, not discovered later.

0.4 **Measure the migration case, not only the greenfield case.** *(CPO blocking condition C1.)*
The control group proves keyless manifests update correctly when installed **keyless from the
start**. Nothing yet measures what the updater does when a *recorded* `"version": "0.0.0-dev"`
in `installed_plugins.json` meets a manifest with **no** version key — and that is the state
every existing Soleur install is in. Build the fixture in that transition shape: install with a
versioned manifest, remove the key at the source, refresh, and record whether the update is
applied, which cache directory is resolved, and what `installed_plugins.json` holds afterwards.
Until this is measured, P1 is verified for new installs and merely *asserted* for upgrades — and
upgrades are the entire population.

0.5 Record the `autoUpdate: true` refresh cadence. The `soleur` entry in
`known_marketplaces.json` carries the key and the other three marketplaces do not, so the
destructive refresh arm is reachable without the user typing anything. Determine when it fires
by observation; do not infer it from `lastUpdated` timestamps.

0.6 **Rehearse the delivery step itself, not only the manifest semantics.** *(Advisor consult.)*
Phase 0.1–0.5 measure what the manifests *mean*; none of them exercises the step the plan says
is broken. Before Phase 1 is called done, run a real marketplace refresh of the 215 MiB
repository **from the actual migration state**, using the persistent setting Phase 3.1 selects.
Otherwise "fixed" is asserted on a path nobody has traversed.

0.7 **Grep for version consumers mechanically, before deleting the key.** The
`docs/_data/plugin.js` consumer was found by reading and confirmed by a later cross-consumer
grep; that ordering is the failure mode, not the finding. Run the sweep as a gate — literal
`\.version`, bracket access `\["version"\]`, and whole-object reads of either manifest — across
`plugins/`, `apps/`, `scripts/`, `.claude/`, `.github/`. One missed consumer is the same class of
defect the `jsonLdSafe` throw already demonstrated.

0.9 **Sweep the plugin-ID and marketplace-URL consumers — the same discipline as 0.7, applied to
the thing the new marketplace changes.** Phase 1B changes the plugin ID for new installs, and
`soleur@soleur` is not only prose. Measured 2026-08-12, four live sites pair a
`plugin_marketplaces:` URL with a `plugins:` ID in a `claude-code-action` step:

| Site | Marketplace URL | Ships to |
|---|---|---|
| `.github/workflows/test-pretooluse-hooks.yml` | `https://github.com/jikig-ai/soleur.git` | This repo's CI |
| `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` | `https://github.com/jikig-ai/soleur.git` | **A user's generated workflow** |
| `plugins/soleur/skills/schedule/SKILL.md` (two blocks) | templated `<REPO_OWNER>/<REPO_NAME>` | **A user's generated workflow** |

Two findings fall out and both belong in the record:

- **These runners clone 181 MiB on every scheduled run.** Defect 2 has a second affected
  population that this plan had not named — GitHub Actions runners, per run, at whatever cadence
  the cron fires. That is an argument *for* migrating them, not merely a chore.
- **`plugins/soleur/test/operator-digest-workflow.test.sh` asserts
  `plugin_marketplaces:.*jikig-ai/soleur`.** If the new repo is named with `jikig-ai/soleur` as a
  prefix (`jikig-ai/soleur-marketplace`, say), that regex **still matches** and the test passes
  whether or not the migration happened. This is the vacuously-true-assertion class plan review
  already caught once in AC6. Anchor the assertion on the full repo path, not a prefix.

Decide per site: migrate now, or stay on the old marketplace with the reason recorded. Both are
defensible; silence is not.

0.8 **Halt conditions — each with a defined branch, because a halt with no alternative is a
stall.**

| Probe | Failure | Branch |
|---|---|---|
| **0.0** | **`git-subdir` materialises ≥ 50 MiB, or misses the 120 s default timeout** | **STOP the run.** Not a fallback — a halt. Outcome (b) rested on this premise and it is refuted, so the operator decides again with the number in hand. Concretely: mark UC-1's resolution superseded (append to `decision-challenges.md`, do not rewrite the RESOLVED block), revert the frontmatter to `refs: 7471`, and put the three coherent outcomes back on the table — (a) and (c) both survive a refutation of the premise, (b) does not. Do **not** proceed to Phase 1B, and do **not** silently degrade to "ship Phase 1 + Phase 3 and call it outcome (a)"; that is the operator's call, not the run's |
| 0.2 | The SHA fallback does not fire for a relative-path plugin source | Option A is refuted for the *relative-path* source shape. **0.0 has already told you whether `git-subdir` — a different source type — behaves differently**, so this is now an ordering question, not an open one: if 0.0 passed, the keyless manifest is re-probed against the `git-subdir` entry before option A is declared dead. Do not stall |
| 0.4 | The migration resolves to the stale `0.0.0-dev/` directory | Option A needs an explicit migration step (uninstall/reinstall guidance) before it ships. Phase 1 does not begin without one |
| 0.6 | The refresh still cannot complete from the migration state with the persistent setting | The stopgap does not deliver for the **old** marketplace entry. That is no longer a blocker on the fix arriving — Phase 1B is the delivery path — but it is a blocker on the *existing install's* migration story, so record it and make the migration sequence the documented route rather than the refresh |
| 0.7 | A version consumer exists outside the known set | Add it to Phase 1 and re-run the sweep |
| **0.9** | **A plugin-ID or marketplace-URL consumer exists outside the four measured sites** | Add it to the 0.9 decision table and re-run the sweep. A consumer that ships inside `plugins/soleur/skills/` reaches users' generated workflows, so it is not optional to enumerate |

### Phase 1 — Remove the sentinel

1.1 Delete the `"version": "0.0.0-dev"` line from
`plugins/soleur/.claude-plugin/plugin.json`. Leave every other key untouched — `mcpServers` in
particular is consumed by `.claude/hooks/session-rules-loader.sh` and
`apps/web-platform/server/agent-runner.ts`.

1.2 Delete the `"version": "0.0.0-dev"` line from the `plugins[0]` entry of
`.claude-plugin/marketplace.json`. **Do not touch the top-level `"version": "1.0.0"`** — that
is the manifest-format version, a different field with a different meaning.

1.3 **Guard `plugins/soleur/docs/_data/plugin.js` — this is a required step, not a footnote.**
Without it the manifest edit alone turns CI red: `plugin.version` becomes `undefined` on the
`SOLEUR_DOCS_OFFLINE=1` path, `jsonLdSafe` throws on it, and `base.njk` is the base layout for
every page. Set an explicit fallback — `plugin.version = data.version ?? "unknown"` matches the
string the CLI itself records and keeps the JSON-LD well-formed. Land it **in the same commit**
as the manifest edit; the two are one atomic change.

1.4 Add the regression test the guard needs: build under `SOLEUR_DOCS_OFFLINE=1` and assert the
`softwareVersion` JSON-LD block still parses. `plugins/soleur/test/seo-aeo-drift-guard.test.ts`
and `marketing-content-drift.test.ts` already spawn that build in `beforeAll`, so they will fail
loudly without the guard — but neither asserts the JSON-LD *shape*, which is the property that
matters here.

### Phase 1B — Publish the additive marketplace source

**Gated on Phase 0.0 passing.** Numbered `1B` rather than renumbering the plan, so every existing
cross-reference and the tasks file stay valid.

**Additive, not a replacement.** `jikig-ai/soleur` remains a valid marketplace with its existing
entry intact. Nothing about an existing install changes as a consequence of this phase; the
plugin ID changes for **new** installs only.

1B.1 **Confirm the repo name and visibility with the operator before creating anything.** The
UC-1 resolution authorises creating the repo; it does not name it. Two properties are decided by
the operator at execution time, not assumed here:

- **Name.** Every candidate in the discussion so far (`soleur-marketplace`) is illustrative. The
  name propagates into the plugin ID, the docs, and the 0.9 sweep, so it is confirmed once and
  then used consistently. **Note the prefix trap from 0.9:** any name beginning `soleur` makes
  `jikig-ai/soleur` a substring, which is what silently passes
  `operator-digest-workflow.test.sh`'s current regex.
- **Visibility.** It must be **public** for `claude plugin marketplace add` to work
  unauthenticated. If the operator wants it private, F does not function and that is a decision,
  not a detail.

Create it with `/soleur:provision-github` rather than by hand, so the step is automated and
audited like every other repo this project provisions.

1B.2 **Contents of the new repo — deliberately minimal, because its size *is* the feature.**

| Path | Content |
|---|---|
| `.claude-plugin/marketplace.json` | `name` (this string, **not** the repo name, becomes the `@marketplace` half of the plugin ID), `owner`, and exactly one `plugins[]` entry |
| `README.md` | What it is, why it exists, and a pointer back to `jikig-ai/soleur` as the source of truth. It must say the two repos are not alternatives to choose between — one is the source, one is the delivery surface |
| `LICENSE` | Mirror `BUSL-1.1` from `plugins/soleur/.claude-plugin/plugin.json`'s `license` key |

Nothing else. No history, no assets, no vendored copy of the plugin. If it grows past a few
hundred KB, the reason it exists has been lost.

1B.3 **The plugin entry shape.** One entry, `git-subdir`, pointing back at this repository:

```json
{ "name": "soleur",
  "description": "…",
  "source": { "source": "git-subdir",
              "url": "https://github.com/jikig-ai/soleur.git",
              "path": "plugins/soleur" } }
```

Two decisions inside that shape:

- **No `version` key**, for the same reason Phase 1 deletes it from the other two manifests. The
  new marketplace must not reintroduce the sentinel through the back door — this is the third
  manifest, and AC1's two-sided assertion becomes three-sided.
- **No pinned `ref` / `sha`.** Anthropic's 42crunch/adobe precedent pins both, which is right for
  a third-party plugin they do not control. Soleur controls this source, and pinning a `sha`
  would recreate defect 1 in a new location: a constant pin that never advances is a frozen
  sentinel wearing different clothes. Track `main`. **Record this as a deliberate divergence from
  the cited precedent**, because the next reader will otherwise assume it was an oversight.

1B.4 **The plugin ID changes for new installs.** Today: `soleur@soleur`, cache at
`~/.claude/plugins/cache/soleur/soleur/<version>/`. The `@` half is the marketplace manifest's
`name` field, and the cache path is `cache/<marketplace name>/<plugin name>/<version>` — read off
the measured control-group entry
(`.../cache/claude-plugins-official/pr-review-toolkit/unknown`), not from documentation. So the
new install resolves to `soleur@<new marketplace name>` at
`~/.claude/plugins/cache/<new marketplace name>/soleur/unknown/`.

**The third component is an inference under a source type nobody has measured.** The control
group is a `github` marketplace with relative `./plugins/<name>` entries; `git-subdir` may key the
cache differently. Phase 0.0 already installs through a `git-subdir` entry — **record the actual
resolved `installPath` from that run** and use the measured string everywhere downstream. Do not
propagate the inferred one.

1B.5 **Update the documented install path** on the surfaces this plan already edits
(`README.md`, `plugins/soleur/README.md`, `plugins/soleur/docs/pages/getting-started.njk`) to
add the new marketplace as the recommended path, and to state plainly that the existing path
still works. Both are true; presenting one as broken would be false, and presenting them as
equivalent would hide the 181 MiB.

**Scope note for Gate 4.9, surfaced rather than assumed.** The operator's accepted determination
(no `.pen` wireframe) was made for two specific copy-only edits: text inside one `<pre><code>`
block and one FAQ answer plus its JSON-LD twin. This step enlarges the `getting-started.njk` edit
— a second install path presented alongside the first, with a recommendation between them. It is
still text inside existing blocks with no new page, route, component, or layout, so the Excluded
clause still reads as governing. **But the determination was granted against a smaller edit, so
the enlargement is recorded here rather than quietly absorbed.** If review or the operator wants
it re-taken, the remedy is unchanged and cheap: one `ux-design-lead` invocation. The Gate 4.9
section itself is not amended — the acceptance recorded there is a decision about what was in
front of the operator at the time.

1B.6 **Write the migration sequence for an existing install.** It is short and, critically, it
never clones the monorepo — which is what makes it usable where the old `remove → re-add →
reinstall` was not:

```
claude plugin marketplace add jikig-ai/<new repo>
claude plugin install soleur@<new marketplace> --scope project --project-path <path>
claude plugin uninstall soleur@soleur --scope project --project-path <path>
claude plugin marketplace remove soleur          # optional; frees the 373 MiB checkout
```

Include the CLI restart (`plugin update --help`: "restart required to apply") and the
`soleur.bak` / old-cache reclaim from Phase 3.6. Every command carries its scope —
`scope: project`, `projectPath: /home/jean/git-repositories/skouer/Skouer` — per plan review
finding 3; a bare command targets user scope and finds nothing.

1B.7 **Apply the 0.9 decisions** to whichever of the four `soleur@soleur` consumers the sweep
says to migrate, and fix `operator-digest-workflow.test.sh`'s prefix-matching assertion in the
same commit whether or not that workflow moves — the assertion is wrong either way.

### Phase ordering note — recovery precedes the manifest edit

*(Advisor consult, applied.)* The phase numbering below reads as "fix, then document". That is
backwards for this change. The Phase 1 fix ships **inside** the manifest, and a user sees the new
manifest only through a marketplace refresh — the operation defect 2 breaks. The persistent
timeout setting is therefore **not a Phase 3 stopgap; it is Phase 1's delivery mechanism.**
Phase 3.1 (verify the persistent-env route) and Phase 0.6 (rehearse a real refresh from the
migration state) both gate Phase 1 being *complete*, not merely *merged*.

**Revised under the UC-1 resolution.** Phase 0.0 runs first, before everything, because Phase 1B
and the re-scoped Phases 2 and 4 are all built on it. Phase 1B then supplies a *second* delivery
mechanism that does not depend on the old refresh at all, which demotes the ordering constraint
above rather than removing it — the old marketplace stays live, so 3.1 and 0.6 still gate the
residue. Execution order:

**0.0 → 0.1–0.5, 0.7, 0.9 → 3.1 → 0.6 → 1 → 1B → 2 → 3.2–3.7 → 4 → 5.**

### Phase 2 — Reconcile the governance corpus

The sentinel is prose-enforced in **five** places — four instruction sites plus ADR-178, which
CTO review found and this plan's first draft missed. All five now assert something false, and a
rule that is false is worse than no rule.

**Re-scoped by the UC-1 resolution: these sites describe the FINAL delivery shape, once.** This
was the core of the challenge — Phases 2 and 4 were the artifacts a later marketplace change
would rewrite, and landing them against the *current* shape meant writing them twice. They are
now written against the post-Phase-1B shape: two marketplaces (`jikig-ai/soleur` retained,
`jikig-ai/<new repo>` recommended), keyless manifests in **three** places, and identity carried
by the source commit SHA. Where a site names a cache path or a plugin ID, it names the new one
and notes that the old one persists for existing installs. Nothing here is written twice.

2.1 `AGENTS.rules.md` — `wg-never-bump-version-files-in-feature`. The *gate* is still correct
(feature branches must not introduce a version) and its id is immutable
(`cq-rule-ids-are-immutable`). Only the trailing clause naming a "frozen sentinel" changes:
there is no version field to leave alone any more. Re-measure the always-loaded budget with
`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` before and after —
the edit should be net-negative, but the number is the authority, not the expectation.

2.2 `plugins/soleur/AGENTS.md` pre-commit checklist — the "Do NOT edit: `plugin.json` version
field (frozen sentinel `0.0.0-dev`)" bullet.

2.3 `plugins/soleur/skills/ship/SKILL.md` — the "Never edit version fields" bullet.

2.4 `CONTRIBUTING.md` — the "Plugin changes" section's sentinel sentence.

2.5 **`ADR-178` is the fifth site, and its cache path must be reconciled against the NEW plugin
ID — not merely against the keyless manifest.** Anchor on content, not line numbers
(`cq-cite-content-anchor-not-line-number`): the passage containing the literal
`~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/`, and the sentence containing *"so the cache
directory name never changes and there is no version bump to trigger an update."* Both become
false, and they become false in **two** independent ways, which is the whole reason this edit is
worth doing once rather than twice:

| Component | ADR-178 asserts | After Phase 1 | After Phase 1 **and** Phase 1B (new installs) |
|---|---|---|---|
| Marketplace segment | `soleur` | `soleur` (unchanged) | `<new marketplace name>` |
| Plugin segment | `soleur` | `soleur` (unchanged) | `soleur` (unchanged) |
| Version segment | `0.0.0-dev`, "never changes" | `unknown`, refreshed in place | `unknown`, refreshed in place |

The amendment states the post-1B path as current, records the post-1 path as what an existing
install resolves to, and replaces the "never changes / no version bump to trigger an update"
reasoning with the SHA comparator. **Use the `installPath` measured in Phase 0.0/1B.4, not the
inferred one** — the third segment under a `git-subdir` source is unverified until that run.

ADR-178 merged last week and is `active`; it is not an archive record. It has **no YAML
frontmatter and no `status:` key** (it uses `- **Status:** Accepted`), so do not look for
`status: active` there.

2.6 Sweep for stragglers: `git grep -n '0\.0\.0-dev'` must return only historical records —
archived plans, specs, brainstorms, learnings, and ADR bodies describing the past. Any *live*
instruction still naming the sentinel is a Phase 2 miss. Do **not** rewrite the archived
artifacts; they are point-in-time records and are correct about the world they describe.

### Phase 3 — Recovery and the clone-timeout stopgap

Not garnish on Phase 1. Per the delivery paradox above, the Phase 1 fix reaches a user only
through the marketplace refresh that defect 2 breaks — and for the one current install the
checkout is already destroyed, so this phase carries the sole route back to a working install.

3.1 **Verify the persistent-env route before documenting it.** A command prefix
(`CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS=900000 claude plugin marketplace update soleur`) sets the
variable for that one invocation only, and `autoUpdate: true` fires refreshes inside ordinary
sessions where no prefix applies. Confirm that an `env` block in `~/.claude/settings.json` is
honoured by the plugin git path — this machine's settings file has no `env` block today, so the
route is untested. If it is not honoured, fall back to a shell-profile export and say so
plainly. Document whichever one is measured to work, never the one that ought to.

3.2 Write the recovery + stopgap entry covering: what the timeout error looks like, the
persistent setting from 3.1, and the remove → re-add → reinstall sequence for a checkout a
previous attempt destroyed. Name it as a workaround for an upstream defect and link the 3.4
tracking issue — an undated workaround with no expiry becomes permanent.

3.3 **Put it where users read, not only where maintainers read.** `README.md` and
`plugins/soleur/README.md` are GitHub; marketing sends people to `soleur.ai/getting-started`.
Extend to `plugins/soleur/docs/pages/getting-started.njk`, and correct
`plugins/soleur/docs/pages/changelog.njk` — its upgrade FAQ currently states *"Run `claude
plugin install soleur` to get the latest version. The plugin manager handles the update
automatically."* That is **affirmatively false today** and stays false after Phase 1 unless
corrected, and it is duplicated into a JSON-LD `FAQPage` block fed to AI answer engines on a
site this repo actively AEO-optimises. Correcting a false machine-readable claim is the point;
the env-var note is secondary.

3.4 ~~File the option F follow-up.~~ **Withdrawn — option F ships in this PR as Phase 1B.** The
issue that would have carried it is not filed; there is nothing left in it to track. What the
deferral was carrying that still needs a home is redistributed rather than dropped:

- The `git-subdir` premise measurement was that issue's task 1 → it is now **Phase 0.0**.
- The `#1439` (recruit 10 founders) dependency was the reason for milestone-targeting the
  deferral. With F landing now, #1439 is no longer *blocked* by it — but the relationship is
  still worth one line in the PR body, because "the delivery path was fixed before the cohort
  arrived" is the fact a future reader of #1439 will want.
- The old marketplace entry keeps `autoUpdate: true` and keeps cloning 181 MiB for anyone on it.
  **That residue does get an issue** — deprecating or redirecting `jikig-ai/soleur` as a
  marketplace, which is an explicit Non-Goal here and a real decision with a migration window.
  Passes the `wg-defer-only-after-inline-triage` triple test: not a ten-line change, observable
  trigger (a second install appearing on the old entry), fires well inside six months.

3.5 File the delivery-canary follow-up (see `## Observability`), with its auth-feasibility check
as the first task.

3.6 File an `action-required`-labelled issue carrying the recovery sequence. `operator-digest`
harvests merged-PR titles and `action-required` issues — **not PR bodies** — so a note in the
body reaches nobody. Give the PR a title that states the user-visible outcome rather than
"fix plugin delivery path", which harvests as a chore.

3.7 Attach this repository's evidence to the upstream defects — the destroyed-checkout
reproduction in particular, which the existing upstream issues describe less precisely than the
measurements here.

### Phase 4 — Architecture record

**Re-scoped by the UC-1 resolution: this phase models the FINAL delivery shape, once.** The
challenge's second argument was that Phase 4 was about to model the *current* topology in C4 for
the first time and then re-model it when the marketplace changed. It no longer does. The C4
edits and the new ADR describe the two-marketplace, `git-subdir`, SHA-identity shape that exists
at the end of this PR. This also answers the simplification panel's "deleting a manifest key does
not change the delivery topology" objection (Plan Review, *Surfaced — Taste*): under the amended
scope **it does** — a new external system, a new delivery edge, and a changed payload boundary.
The cut recommendation is therefore not carried forward, and the reason is recorded here rather
than left as a silently-ignored review finding.

4.1 Amend `ADR-017`. Its `## Decision` names the sentinel and its `## Consequences` claims
"zero manual version management" — the first is now wrong and the second was always true for
the wrong reason. Add the correction plus an `## Alternatives Considered` entry recording why
the CI write-back stays rejected (the CLA-ruleset constraint is unchanged). ADR-017 keeps
`status: active`; this is an amendment, not a supersession.

4.2 Write the new ADR for the delivery decision itself. **Refer to it by slug and assign the
ordinal at file-creation time** — do not pre-claim (plan review: the pre-claim ritual invents
coordination overhead across 64 refs). Its scope widened with the UC-1 resolution and now carries
**two** coupled decisions in one record, because they are one delivery architecture:

- **Identity.** Version identity for an installed plugin is the source commit SHA, obtained by
  omitting the field rather than by publishing a string.
- **Distribution.** The marketplace source is a small dedicated repo whose single entry is a
  `git-subdir` into `jikig-ai/soleur`, published **additively** — the monorepo stays a valid
  marketplace. Record the measured `git-subdir` numbers from Phase 0.0, the deliberate divergence
  from the 42crunch/adobe precedent on pinning (1B.3), and that the payload boundary is now
  `plugins/soleur` rather than the whole repository.

Its `## Consequences` is the home for the risks with nowhere else to live: dependence on
undocumented CLI internals (≥3 recording modes, upstream #79950 actively changing the
comparator); **the two-marketplace state and its cost** — two IDs, two cache trees, a documented
migration, and an old entry that still clones 181 MiB; and the rollback. The rollback statement
is the one plan review corrected and it must survive verbatim in substance: re-adding the
`version` key is a *source-side* edit whose delivery is gated on the refresh it is rolling back,
so the real floor is `remove → re-add → reinstall`, which materialises HEAD unconditionally.
**Phase 1B gives that floor a cheap route it did not have** — re-add against the ~50 KB
marketplace, not the 181 MiB one — and the ADR should say so, because it is the difference
between a rollback that exists on paper and one an operator can run.

4.3 C4. The installed-user delivery path is **entirely unmodeled** — verified by reading all
three of `model.c4`, `views.c4` and `spec.c4`, not by grepping the feature's own noun. The
enumeration:

- **External actors:** the model has `founder`, `betaContact`, `contributor` and no actor for
  an *installed Soleur user* running the plugin on their own machine. Missing.
- **External systems:** `github` is modeled as "Source control, CI/CD, issue tracking, and
  releases" with no distribution edge for plugin delivery. The Claude Code CLI *on a user's
  workstation* is modeled nowhere — `engine`/`claude` is the server-side Cloud CLI Engine.
  Missing.
- **Containers / data stores:** the user's local marketplace checkout and plugin cache
  (`~/.claude/plugins/marketplaces/…`, `~/.claude/plugins/cache/…`) have no element. Missing.
- **Access relationships:** no edge represents "the installed CLI clones the marketplace from
  GitHub and materialises the plugin into a local cache". Missing.
- **A description this change falsifies:** the `plugin` system's own description already says
  it ships primitives "for execution on an installed user's machine" — an assertion with no
  element behind it. Correct it or give it the element it presumes.

- **Added by the UC-1 resolution:** the **marketplace source repo** is a distinct external
  system, not a detail of `github`. It is the element that carries the whole point — a small
  delivery surface fronting a large source repo — and modelling delivery without it would model
  the shape this PR replaces. Its edges: *installed CLI → marketplace repo* (clone the catalogue,
  ~50 KB) and *marketplace repo → `jikig-ai/soleur`* (`git-subdir` resolution, ~17 MiB measured
  floor). The two edges carrying different payload sizes **is** the architecture; a single
  undifferentiated "clones from GitHub" edge would say nothing.

Add the actor, the local cache store, the marketplace source repo, and the delivery
relationships; tag the external ones `#external`; and add both endpoints of every new edge to the
`context` view's `include` list — per the `#7332` note already in `views.c4`, an edge renders only
when *both* endpoints are included, and a node added to a view containing neither endpoint
renders as a disconnected box. **`platform.plugin` is not currently in that include list**, so a
delivery edge terminating there needs it added explicitly.

**Then run `scripts/regenerate-c4-model.sh` and commit
`knowledge-base/engineering/architecture/diagrams/model.likec4.json`.** It is an 801 KB
*committed render artifact* that `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs
against a fresh render, and that suite — **not** `c4-code-syntax.test.ts` (a CodeMirror tokenizer
unit test that never reads a `.c4` file) and **not** `c4-render.test.ts` (which fully mocks
`spawn`/`fs`; its "Could not resolve reference" string is a fixture) — is the real gate. Both of
those still run, but neither can fail on a broken model.

### Phase 5 — Verification

5.1 Run the plugin test suite and the repo's `--check` gates
(`bash scripts/sync-readme-counts.sh --check`) to confirm nothing asserted on the removed key.

5.2 Re-run the Phase 0 fixture against the *edited* manifests and record the resulting
`gitCommitSha`.

5.3 Confirm the docs build still emits a well-formed `softwareVersion` on both the online and
`SOLEUR_DOCS_OFFLINE=1` paths.

## Files to Edit

| File | Change |
|---|---|
| `plugins/soleur/.claude-plugin/plugin.json` | Delete the `version` key |
| `.claude-plugin/marketplace.json` | Delete `plugins[0].version`; leave the top-level `version` |
| `plugins/soleur/docs/_data/plugin.js` | **Required guard** — `data.version ?? "unknown"`; without it CI is deterministically red |
| `plugins/soleur/test/seo-aeo-drift-guard.test.ts` *(or a sibling)* | Assert the offline build's `softwareVersion` JSON-LD parses |
| `AGENTS.rules.md` | `wg-never-bump-version-files-in-feature` trailing clause (id unchanged) |
| `plugins/soleur/AGENTS.md` | Pre-commit checklist sentinel bullet |
| `plugins/soleur/skills/ship/SKILL.md` | "Never edit version fields" bullet |
| `CONTRIBUTING.md` | "Plugin changes" sentinel sentence |
| `README.md` | Recovery + persistent-env stopgap entry |
| `plugins/soleur/README.md` | Same entry |
| `plugins/soleur/docs/pages/getting-started.njk` | Same entry — the surface marketing actually sends people to |
| `plugins/soleur/docs/pages/changelog.njk` | **Correct the false upgrade FAQ** in both the rendered copy and its JSON-LD `FAQPage` block |
| `knowledge-base/engineering/architecture/decisions/ADR-017-version-from-git-tags.md` | Amendment + alternatives entry |
| `knowledge-base/engineering/architecture/decisions/ADR-178-shared-bash-primitives-ship-in-plugin.md` | Amend the cache-path consequences (lines 38, 224) that this change falsifies |
| `knowledge-base/legal/article-30-register.md` | Amend PA-32 §(f) to name the marketplace clone channel |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Installed-user actor, local cache store, delivery edge; correct the `plugin` description |
| `knowledge-base/engineering/architecture/diagrams/views.c4` | Add both endpoints of each new edge to `context`, **including `platform.plugin`** |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | **Regenerate** via `scripts/regenerate-c4-model.sh` — committed render artifact, byte-diffed by `c4-model-freshness.test.sh` |
| `plugins/soleur/test/operator-digest-workflow.test.sh` | Fix the prefix-matching `plugin_marketplaces:.*jikig-ai/soleur` assertion (Phase 0.9) — wrong whether or not the workflow migrates |

**Added by the UC-1 resolution (Phase 1B):**

| File | Change |
|---|---|
| `.github/workflows/test-pretooluse-hooks.yml` | Per the 0.9 decision: migrate the `plugin_marketplaces` + `plugins` pair, or record why it stays |
| `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml` | Same decision — **this one ships into a user's generated workflow** |
| `plugins/soleur/skills/schedule/SKILL.md` | Same decision, two `claude-code-action` blocks |

`README.md`, `plugins/soleur/README.md` and `getting-started.njk` already appear above; Phase 1B.5
adds the new marketplace path to the same edit rather than opening a second pass over them.

## Files to Create

| File | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-<n>-*.md` | The delivery decision — identity **and** distribution. **Slug now, ordinal at file-creation time**; do not pre-claim (plan review) |
| `knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/tasks.md` | Task breakdown |

**In the new marketplace repository, not this one** (Phase 1B.2 — listed so the deliverable is
not invisible just because it lands outside this tree):

| File | Purpose |
|---|---|
| `.claude-plugin/marketplace.json` | One `git-subdir` plugin entry, **no `version` key** |
| `README.md` | What it is; pointer back to `jikig-ai/soleur` as source of truth |
| `LICENSE` | `BUSL-1.1`, mirroring the plugin manifest's `license` |

**Glob verification.** Every path in this repo was confirmed to exist with `git ls-files` / `ls`;
the four Phase 1B additions above were confirmed by `git grep -n 'plugin_marketplaces'` and
`git grep -n 'soleur@soleur'` on 2026-08-12. The Files-to-Create entries do not exist yet by
definition. `plugins/soleur/plugin.json` — the path the issue cites — was confirmed **not** to
exist and is deliberately absent from this table.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 64 issues; none of
their bodies contains any of `plugin.json`, `marketplace.json`, `reusable-release.yml`,
`version-bump-and-release.yml`, `CONTRIBUTING.md`, `plugins/soleur/AGENTS.md`,
`AGENTS.rules.md`, or `ADR-017`.

## Compliance (GDPR gate — Phase 2.7)

`/soleur:gdpr-gate` was invoked under expanded trigger **(d) new artifact distribution surface
(plugin update, package release)**; the canonical regex does not match a manifest-only diff.
**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor`
before merging.**

**Verdict: ADVISORY — 0 Critical, 4 Important, 2 Suggestion.** No Critical escalation, so no
`compliance-posture.md` write and no `compliance/critical` issue is required by the gate.

Two caveats that must travel with the verdict. First, the gate's five v1 checks are all
schema- or vendor-shaped, and a manifest-only diff pattern-matches none of them — **the null
result must not be recorded as "gdpr-gate PASS, no exposure."** The Important findings below
are reached by analysis within the gate's articles, and are labelled as such. Second, the gate
reported `POSTURE_FAIL` — its vendored rules are 93 days stale (`last-verified: 2026-05-10`)
and the anti-backdating cron binding is inert (#7255), so that date is operator-attested with
no independent liveness evidence. Both are pre-existing conditions of the gate, not of this
change.

| Finding | Article | Severity | Bears on the option choice |
|---|---|---|---|
| The whole-repo clone industrialises the Art. 17 erasure impossibility PA-32 §(f) already records — converting a bounded, counted population (2 forks) into an unbounded population of full-history clones | Art. 17; Art. 5(1)(e) | Important | **Decided.** Option F selected (Phase 1B): the new-install payload carries neither the corpus nor the 181 MiB history. Narrowed for the new path, **not** retired for the old entry or for existing clones — see "What is NOT retired" |
| Minimisation: **887 of 13,523 delivered files (~93%) and ~94% of bytes are not the product**, including `knowledge-base/legal/` (the Art. 30 register itself, plus 41 counsel-review memoranda) and 333 design screenshots | Art. 5(1)(c); **Art. 25(2)** | Important | **Decided — retired by construction for the new path.** A `git-subdir` payload carries only `plugins/soleur`, so the register, the memoranda and the screenshots are structurally absent rather than policy-excluded. Art. 25(2) is the sharper citation: "already public on GitHub" answers a *disclosure* question, not a *minimisation* one. Retrievable-on-request and pushed-to-every-installer are different operations |
| The redistributed corpus has a live limb with **no available lawful basis** — `compliance-posture.md` Active Item #7119, OPEN and BLOCKING, with #7120 (Art. 14 notice, expired), #7121 (DPIA, ~5 months overdue), #7122 open against the same population | Art. 6(1)(f); Art. 4(2) | Important | Context. **#7471 does not remediate #7119** and must not be recorded as doing so |
| No Art. 30 processing activity covers plugin distribution (`grep -i marketplace` over the register returns zero). Disposition: **amend PA-32 §(f)**, do not create a new PA — no new purpose, data category, recipient category, or sub-processor | Art. 30(1)(d)/(f) | Important | Amendment needed under **every** option |
| No new sub-processor under any candidate — GitHub throughout (option F is another GitHub repo; the remote-URL variant resolves to GitHub Pages). *Lindqvist* C-101/01: world-readable availability is not a Chapter V transfer | Art. 44–49 | Suggestion | Negative. **Re-open if the option becomes non-GitHub** (a CDN, npm, a third-party registry) — that would be a genuinely new sub-processor |
| The `gitCommitSha` the CLI records in the user's `~/.claude/plugins/installed_plugins.json` is **not processing Jikigai controls** | Art. 4(1); Art. 4(7) | Suggestion | Negative determination |
| Art. 9 special-category | — | — | **Did not fire** (no schema in the diff) |

**Two constraints this plan adopts verbatim from the gate.**

1. The `gitCommitSha` determination must be stated as *the conclusion of the register's
   three-limb test* (purpose / credential / infrastructure — all three fail), **never** as
   "the plugin is out of scope." The register was re-keyed at #7331 because a surface-list
   carve-out reading "the locally-installed Soleur plugin is out of scope" was false in both
   conjuncts for an operator-assisted run, after that defect had escaped three times.
   Reintroducing plugin-shaped carve-out language is how a closed class reopens.
2. Narrowing the distribution surface **must not** be claimed to satisfy #7119's R5. Route that
   question to `clo`; do not decide it here.

**Effect on this plan — rewritten under the UC-1 resolution.** Findings 1 and 2 were recorded as
a *contested deferral*. They are no longer contested and no longer deferred: option F ships as
Phase 1B, and the two findings are **retired by construction rather than argued away.**

**What is retired, precisely.** The Art. 5(1)(c) / Art. 25(2) minimisation finding turned on
delivering ~93% non-product files to every installer — `knowledge-base/legal/` (the Art. 30
register itself, plus 41 counsel-review memoranda), 333 design screenshots, and 84 MiB of
`knowledge-base/project/`. A `git-subdir` payload carries **only `plugins/soleur`**, so none of
those files is in it. This is a structural property of the payload boundary, not a policy
undertaking — there is nothing to comply with, because there is nothing to send. The Art. 17
fan-out finding narrows the same way: the new-install path materialises no full-history clone of
the corpus, so it stops converting a bounded population into an unbounded one.

**Use the right number.** The payload is ~17 MiB (measured floor, `## Amendment 2026-08-12`), not
~50 KB — 50 KB is the marketplace repo. The minimisation conclusion does not depend on which
figure is used, and it would not survive citing the wrong one.

**What is NOT retired, and this is the part a compliance reader must not skim.**

1. **Every existing install already holds a full clone.** Retiring a distribution channel does not
   un-distribute what it distributed. The Art. 17 impossibility PA-32 §(f) records is unchanged
   for anything already cloned; Phase 1B narrows the *future* fan-out only.
2. **The old marketplace entry still delivers the whole repository.** `jikig-ai/soleur` stays a
   valid marketplace by deliberate design (additive, not a replacement). Anyone who installs from
   it — and the four CI surfaces in Phase 0.9, on every scheduled run, until they migrate — pulls
   the full 181 MiB of history and the entire non-product corpus. The minimisation finding is
   retired **for the new path**, not for the repository. Deprecating the old entry is the tracked
   Non-Goal that would close it, and until that lands the honest statement is *narrowed*, not
   *eliminated*.
3. **#7119 is untouched.** Per the gate's second adopted constraint, narrowing the distribution
   surface must **not** be claimed to satisfy #7119's R5. That question routes to `clo` and is not
   decided here — a narrower payload is not a lawful basis.

The gate's other confirmation still holds: **item 1 (removing the `version` key) has zero GDPR
surface on its own.**

**Register work, now unconditional rather than option-dependent:**

- Amend **PA-32 §(f)** to name the marketplace clone as a distinct automated clone-generating
  channel, and to record that a second, narrowed channel now exists alongside it. **Change no
  figure** — the "80 committed digests" count is correct and the register was never stale; an
  earlier draft of this plan asserted "81, not 80" by counting the `user-conversations/`
  subdirectory as a digest, and that error must not travel into a legal register. See AC18.
- Add the **new marketplace repository** to the register's in-scope surfaces list.
- Widen the **`GitHub Inc` vendor-row scope cell**, which currently reads "cc-router in-process
  MCP tool surface" and covers neither distribution hosting nor a second repository.
- **No new sub-processor.** The new repo is GitHub, same as the old; the Art. 44–49 Suggestion's
  negative determination is unchanged, and its re-open trigger (a non-GitHub host — CDN, npm, a
  third-party registry) is not fired by this change.

## Observability

This change ships code to a customer's self-hosted CLI — observability layer 7. The honest
statement is that the *delivery* property is only observable from the installed side, and this
repository has no channel to it; the declarations below say what can actually be seen, and name
what cannot.

```yaml
liveness_signal:
  what: "A merge touching plugins/soleur/ produces a GitHub Release whose tag advances, and the
         plugin manifest at that tag carries no `version` key."
  cadence: "Per merge to main matching path_filter plugins/soleur/"
  alert_target: "version-bump-and-release.yml run conclusion (existing wg-after-a-pr-merges-to-main gate)"
  configured_in: ".github/workflows/version-bump-and-release.yml -> reusable-release.yml"
error_reporting:
  destination: "GitHub Actions run status; no new Sentry surface is introduced by this change"
  fail_loud: true
failure_modes:
  - mode: "The version key is reintroduced by a future edit, silently restoring the no-op"
    detection: "jq 'has(\"version\")' over both manifests, asserted in CI"
    alert_route: "CI required check fails the PR"
  - mode: "The CLI stops honouring the SHA fallback in a future release (upstream #79950 is
           actively changing this comparator), so updates silently no-op again"
    detection: "Not detectable from this repository TODAY — the observable lives on an installed
                machine. The compensating control is the delivery canary below, tracked at
                Phase 3.5. Stated as a present blind spot rather than assumed away."
    alert_route: "None today; the canary is the proposal."
  - mode: "A marketplace refresh times out and destroys the checkout with no user action
           (autoUpdate: true)"
    detection: "The canary's CHECK_ERROR verdict. A timeout must never be recorded as CLEAN."
    alert_route: "Scheduled workflow failure"
  - mode: "The docs build emits an undefined softwareVersion on the offline path"
    detection: "Eleventy build under SOLEUR_DOCS_OFFLINE=1 plus a JSON-LD shape assertion"
    alert_route: "docs build failure in CI"
  - mode: "The new marketplace repo's entry drifts — a `version` key is reintroduced, or the
           git-subdir `path` stops pointing at plugins/soleur — silently restoring the whole-repo
           payload or the no-op comparator"
    detection: "NOT detectable by a check in THIS repo: the third manifest lives in the new
                marketplace repository, outside this tree, so the AC12 --check gate cannot reach
                it. The canary is the only observer, which is a reason to build it rather than a
                reason to assume the manifest stays put. Stated as a blind spot, not assumed away."
    alert_route: "Canary CHECK_ERROR / payload-size verdict; none today"
  - mode: "A CI or user-generated scheduled workflow still on `soleur@soleur` clones 181 MiB on
           every run, unnoticed because it succeeds"
    detection: "Phase 0.9's sweep is a point-in-time audit, not a monitor. The repeatable
                observable is the workflow's own step duration in Actions run logs."
    alert_route: "None automated; the 0.9 decision table is the record"
logs:
  where: "GitHub Actions run logs for version-bump-and-release.yml"
  retention: "GitHub default (90 days)"
discoverability_test:
  command: "jq -e 'has(\"version\")|not' plugins/soleur/.claude-plugin/plugin.json && jq -e '.plugins[0]|has(\"version\")|not' .claude-plugin/marketplace.json"
  expected_output: "true\\ntrue (exit 0) — neither manifest declares a version, so the CLI keys updates on the source commit SHA. Measured 2026-08-11 on the unfixed tree: exit 1 with `false`, which is the probe correctly reporting the defect it exists to detect."
```

Runs locally from the repo root, no SSH, first token `jq` (on the probe allowlist), no
credentials required.

### The compensating control (layer 7) — the delivery canary

**Observability layer 7:** code under `plugins/` that executes on a customer's self-hosted CLI
(`hr-observability-layer-citation`). The honest position is that delivery success is not
observable from this side today and no amount of manifest editing changes that. The proposal,
raised by CTO review and tracked at Phase 3.5:

A scheduled workflow on a clean runner with a fresh `HOME` runs the **documented install path
end to end**. This is the layer-7 analogue of `scripts/prod-version-drift-check.sh` (#7091) —
already cited in this plan as the staleness-detector precedent, here extended rather than
re-invented. Adopt its four-verdict discipline, and in particular its stated rule: **a clone
timeout must report `CHECK_ERROR`, never `CLEAN`** — "we could not evaluate" must never be
encoded as "no drift".

**Three changes to the canary's target under the UC-1 resolution.**

1. **It targets the new marketplace, because that is what "the documented install path" now
   means.** `soleur@<new marketplace name>`, added from the ~50 KB source. A canary pointed at
   `soleur@soleur` would monitor the path the plan is steering users off.
2. **It should also probe the old entry, at a lower cadence.** `jikig-ai/soleur` stays a valid
   marketplace and stays the path four CI surfaces and one existing install are on. An
   unmonitored live path is how the next silent failure happens. Its expected verdict is
   `CHECK_ERROR` on timeout, which is information, not noise.
3. **It asserts on content, not on `gitCommitSha`.** Plan review finding 5 measured the metadata
   failing to follow the content (upstream #76882 — in this plan's own defect corpus), so a
   `gitCommitSha == origin/main` clause can be **false after a successful delivery**. Assert that
   a file the merge commit changed is present with its new content inside `installPath`; keep the
   SHA as explicitly-unreliable secondary context.

**The canary also becomes affordable, which is a real consequence and not a footnote.** Against
the old path it clones ~396 MiB per run — a job slow enough that its own cadence would be argued
down. Against the new path it moves ~17 MiB (measured floor) and finishes inside the CLI's
default timeout, which is the same property Phase 0.0 gates. A monitor that is cheap gets run.

**It would have caught both defects before a user did.** That is the argument for building it.

**First task is a feasibility gate, not construction:** determine whether `claude plugin
marketplace add / install / update` function unauthenticated on a runner. If they require
credentials, the canary is blocked and the plan says so rather than designing around an
unverified assumption. **Phase 1B.1 resolves half of this in advance** — the new marketplace repo
must be public for `marketplace add` to work at all, so the repo-visibility half of the question
is already decided; what remains is whether the CLI itself needs credentials.

Two weaker options, recorded and not selected: an in-session staleness banner comparing the
local `gitCommitSha` against `api.github.com/repos/jikig-ai/soleur/commits/main` (needs a new
`SessionStart` hook arm — the existing `welcome-hook.sh` early-exits unless run inside this
repo — and there is **no Sentry sink on a customer CLI**, so `cq-silent-fallback-must-mirror-to-sentry`
has nowhere to mirror; that must be stated, not left silent); and GitHub's
`/repos/jikig-ai/soleur/traffic/clones`, which cannot distinguish a completed clone from a
timed-out one and is supplementary at best.

## Domain Review

**Domains relevant:** engineering, product, legal/compliance.

Marketing was assessed and found **not relevant as a domain review**, though marketing-owned
*surfaces* are edited: the change corrects a false claim on published pages rather than making
a positioning or messaging decision. The CPO assessment covers the positioning dimension.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Direction sound; two blocking defects in the plan as written, both folded in
above. (1) Removing the key does not degrade the JSON-LD — it **throws**, because `jsonLdSafe`
calls `.replace` on `JSON.stringify(undefined)`, and two CI suites spawn the offline Eleventy
build, so the manifest edit alone turns CI deterministically red while the production deploy
stays green. (2) `autoUpdate: true` means the destructive refresh fires without the user
running anything, so a command-prefix env var covers only the manual verb and leaves the
automatic arm at 120s. Also found: ADR-178 is a fifth governance site; the migration
self-delivers exactly once via the `0.0.0-dev` ≠ `unknown` inequality; #71074 orphans one
directory per existing install at migration; the CLI has ≥3 undocumented recording modes and
upstream #79950 will change the comparator, so the rollback (re-add the key) must be recorded.
Verdict on shape: **one PR**, with the canary and the marketplace repo tracked separately.
Cross-consumer grep confirmed `docs/_data/plugin.js` is the only code consumer of the key.

### Product (CPO)

**Status:** reviewed
**Assessment:** **Conditional sign-off** on direction; the version-key deletion is endorsed
without reservation. Three blocking conditions, all folded in: C1 measure the
`0.0.0-dev` → keyless *migration* case (the control group only covers keyless-from-the-start,
while every existing install is in the transition state); C2 the cut list deferred P5 while
having cut P4 *because* P5 would fix it, so P4 is left ungated and unrepaired; C3 the stopgap
must reach the docs site, and `changelog.njk`'s upgrade FAQ is affirmatively false today.
Population calibrated: **beta users = 1**, alpha tester #1 onboarded 2026-08-06 on this exact
path — the affected set and the total set are identical. The product cost named is not the
stale skills but the checkmark: a tool that reports success while delivering nothing attacks
the delegation axis the brand sells on, and confirms the #1 objection recorded across 8/10
tested personas. Stale users do **not** get unstuck automatically. The deferred P5 fix becomes
cohort-wide when #1439 resumes, so it should be milestone-targeted with that dependency
recorded.

### Legal / Compliance

**Status:** reviewed — see the `## Compliance (GDPR gate)` section above.
**Assessment:** ADVISORY, 0 Critical / 4 Important / 2 Suggestion. Two Important findings bear
directly on the option choice (Art. 17 clone fan-out; Art. 25(2) minimisation at ~93% non-product
files). PA-32 §(f) needs amending under every option. Item 1 alone has zero GDPR surface.
**Updated 2026-08-12:** option F is selected, so those two findings are retired **by construction
for the new install path** — the payload no longer contains the files the minimisation finding
named. They are **not** retired for existing clones or for the retained `jikig-ai/soleur` entry;
the Compliance section states that boundary explicitly, and #7119 remains untouched and routed to
`clo`.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

**Tier rationale — declared explicitly because the mechanical override is arguable.** Two
`.njk` files are in `## Files to Edit`, and the glob superset in
`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` matches `**/*.{njk,html,…}`.
The same document's **Excluded** list carves out *"Pure copy or style tweaks with no
structural/layout change"*, which is exactly what these edits are: the text of a `<pre><code>`
block and the wording of an FAQ answer plus its JSON-LD twin. No page, route, component,
layout, flow, or template *structure* changes, and nothing new is rendered. Tier is therefore
declared **ADVISORY**, not BLOCKING, and no `.pen` wireframe is required.

This is recorded rather than silently resolved because the glob and the exclusion clause point
opposite ways and the wireframe gate is fail-closed by design. **Plan-review should overturn
this to BLOCKING if it disagrees** — the cost of doing so is one `ux-design-lead` invocation.

## Encryption Posture

```yaml
at_rest:
  - store: "The installed user's local plugin cache (~/.claude/plugins/cache/soleur/…)"
    mechanism: "None — plaintext on the user's own filesystem, under their own account"
    evidence: "Directory listing on this machine; the CLI writes an unencrypted tree"
    defends_against: "Nothing; it is not a protection mechanism"
    does_not_defend: "Local disk theft, other local processes running as the same user"
    disclosed_as: "Not disclosed — it is the user's own machine, holding a copy of a public repository's plugin subtree. No Soleur-controlled data is stored there."
    live_verification: "ls ~/.claude/plugins/cache/soleur/"
in_transit:
  - connection: "Installed Claude Code CLI -> github.com (marketplace clone / refresh)"
    tls: "HTTPS (or SSH where the user's git config rewrites it)"
    cert_verification: "on"
    does_not_defend: "GitHub-side compromise; a user-configured insteadOf rewrite pointing elsewhere"
    disclosed_as: "Not separately disclosed — this is git-over-HTTPS against a public repository, an edge that already exists and is unchanged by this plan"
```

No new persistent store and no new cross-component connection is introduced. The `exception`
block is absent because no plaintext exception or disabled cert verification is proposed.

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1 — the sentinel is gone from both manifests.**
   `jq 'has("version")' plugins/soleur/.claude-plugin/plugin.json` returns `false`, and
   `jq '.plugins[0]|has("version")' .claude-plugin/marketplace.json` returns `false`.
2. **AC2 — the manifest-format version is untouched.**
   `jq -r '.version' .claude-plugin/marketplace.json` still returns `1.0.0`.
3. **AC3 — no other manifest key was disturbed.**
   `jq -r 'keys|sort|join(",")' plugins/soleur/.claude-plugin/plugin.json` equals the pre-change
   key list minus `version`, verbatim. `mcpServers` is present with all four servers.
4. **AC4 — the SHA-fallback claim was verified against a Soleur-shaped source, not only against
   the control group.** The Phase 0.2 fixture run is recorded in the PR body with the
   `gitCommitSha` observed before and after a second commit, and the two differ. If the fixture
   could not be built, the PR states so and AC4 fails rather than being waived.
5. **AC5 — the control group reading is reproduced.** For **all six** named plugins,
   `jq 'has("version")' <manifest>` returns `false`, and each corresponding
   `installed_plugins.json` entry carries a `gitCommitSha`. **Three corrections from plan review,
   all of which made the AC unrunnable:** the prose said "three named" while the plan names six;
   the path template is wrong for two of them — `github` and `playwright` live under
   `external_plugins/`, not `plugins/`, so the templated path 404s; and the quoting was
   unbalanced. The substance was re-verified and holds: all six have `has("version") == false`
   and share `gitCommitSha 20a5a1f1…`. Only the addressing was broken.
6. **AC6 — every live instruction naming the sentinel is corrected. Two greps, because one is
   not enough.**
   - **(a) The literal.** `git grep -n '0\.0\.0-dev'` returns **zero** hits in
     `plugins/soleur/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`,
     `plugins/soleur/AGENTS.md`, `plugins/soleur/skills/ship/SKILL.md`, `CONTRIBUTING.md`, and
     the two amended ADRs' *live* claims. Remaining hits are historical records only — measured
     at plan time, those live under `knowledge-base/project/plans/` (7 files, **not all under
     `archive/`**), `knowledge-base/project/plans/archive/`,
     `knowledge-base/project/specs/feat-tag-only-versioning/` (**a non-archive spec**),
     `knowledge-base/project/specs/archive/…`, `knowledge-base/project/brainstorms/`, and
     `knowledge-base/project/learnings/`. The first draft of this AC named only the `archive/`
     paths and would have failed against a correct implementation.
   - **(b) The paraphrase.** `AGENTS.rules.md` says *"frozen sentinel"* **without** the literal
     string, so grep (a) passes while the rule still asserts something false. Also assert
     `git grep -n 'frozen sentinel'` returns zero hits in `AGENTS.rules.md`,
     `plugins/soleur/AGENTS.md`, `CONTRIBUTING.md`, and `plugins/soleur/skills/ship/SKILL.md`.
7. **AC7 — the rule id is unchanged and the always-loaded budget did not grow.**
   `grep -c 'id: wg-never-bump-version-files-in-feature'` returns 1 in `AGENTS.rules.md` and 1 in
   `AGENTS.md`. `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`
   reports a `B_ALWAYS` **no greater than the measured baseline of 44593** bytes
   (`AGENTS.md=5341 + AGENTS.rules.md=39252`, captured 2026-08-11). That baseline is already in
   the lint's `[WARN]` tier against the 46000-byte ratchet, so this edit must be net-neutral or
   net-negative — it removes a clause and adds none.
8. **AC8 — the offline docs build succeeds and its JSON-LD parses.** The Eleventy build exits 0
   both with and without `SOLEUR_DOCS_OFFLINE=1`, and in the offline output the
   `softwareVersion` value is a non-empty JSON string. Asserted by a test, because without the
   Phase 1.3 guard this build **throws** — the failure is a `TypeError` in `jsonLdSafe`, not a
   cosmetic value. `plugins/soleur/test/seo-aeo-drift-guard.test.ts` and
   `marketing-content-drift.test.ts` both pass. **Scope extended by plan review:** `github.js`
   sets `version: null` in **three** places, not one — the `SOLEUR_DOCS_OFFLINE` hatch (line 25),
   the fetch `catch` (line 51), and the `?? null` no-release path (line 59). So the claim that
   "the production docs deploy stays green because a real release tag is present" holds *only
   while the GitHub API call succeeds*: post-change, a transient API failure during a production
   docs build throws and kills every page. AC8 must also exercise the **API-failure arm**, not
   just the offline flag.
9. **AC9 — ADR-017 is amended, not silently contradicted.** Its `## Decision` no longer asserts
   the sentinel, it carries an `## Alternatives Considered` entry recording why the CI
   write-back stays rejected (including the pre-merge feature-branch-write variant, which fails
   for a different reason: it collides with `wg-never-bump-version-files-in-feature` and
   guarantees conflicts across concurrent PRs), and its `status:` is still `active`.
9. **AC9b — ADR-178's falsified consequences are amended.** Anchored on **content, not line
   numbers** (`cq-cite-content-anchor-not-line-number`): neither the passage containing the
   literal cache path `~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/` nor the sentence
   containing *"so the cache directory name never changes"* still asserts that as current. Note
   ADR-178 has **no YAML frontmatter and no `status:` key** — it uses `- **Status:** Accepted` —
   so do not go looking for `status: active` there; that is ADR-017's format, not ADR-178's.
10. **AC10 — the new ADR exists, and its ordinal is unique against `origin/main` at creation
    time.** No pre-claim, no merge-window re-derivation, no sweep of every artifact naming it —
    plan review cut that ritual. The plan and `tasks.md` refer to the ADR by **slug**, so a
    collision costs a filename, not a sweep.
11. **AC11 — the C4 delivery path renders, and the gate is the one that can actually fail.**
    `model.c4` declares the installed-user actor, the local plugin-cache store, **the new
    marketplace source repo**, and the delivery relationships; `views.c4`'s `context` view
    includes **both** endpoints of each new edge, **`platform.plugin` among them**;
    `model.likec4.json` is regenerated via `scripts/regenerate-c4-model.sh` and committed; and
    **`plugins/soleur/test/c4-model-freshness.test.sh` passes.** That byte-diff suite is the real
    gate — `c4-code-syntax.test.ts` is a CodeMirror tokenizer test that never reads a `.c4` file
    and `c4-render.test.ts` mocks `spawn`/`fs`, so the earlier draft of this AC named two tests
    that **cannot fail on a broken model** and would have passed over one.
12. **AC12 — a CI check now asserts the manifests stay keyless,** following the repo's
    established `--check` shape rather than a write-back, so the defect cannot silently return.
13. **AC13 — the remaining deferrals are tracked. Rewritten: the option F issue is no longer one
    of them.** Option F ships as Phase 1B, so no issue is filed for it and none is expected. What
    must exist: the **old-marketplace-deprecation** issue (the residue named in Phase 3.4), and
    the delivery-canary issue with its auth-feasibility check as task 1. The in-session banner is
    an explicit Non-Goal with its trigger stated. **An AC that requires a now-shipped deferral to
    be filed as an issue would fail a correct implementation** — this is the same class of defect
    plan review caught in AC5 and AC6.
14. **AC14 — the stopgap names its own expiry and is on the surfaces users read.** The entry
    appears in `README.md`, `plugins/soleur/README.md`, and
    `plugins/soleur/docs/pages/getting-started.njk`; it states that it is a workaround for an
    upstream defect. **Its expiry link changes:** it no longer points at the option F issue
    (which does not exist) but at the old-marketplace-deprecation issue, because the stopgap's
    scope is now exactly the old entry's residue.
15. **AC15 — the false upgrade claim is corrected in both of its forms.**
    `plugins/soleur/docs/pages/changelog.njk` no longer asserts that the plugin manager handles
    the update automatically, in **either** the rendered FAQ copy or the JSON-LD `FAQPage`
    block — a corrected page with a stale structured-data twin still feeds the old claim to
    answer engines.
16. **AC16 — the documented stopgap is the one that was measured to work.** Phase 3.1 recorded
    whether an `env` block in `~/.claude/settings.json` is honoured by the plugin git path; the
    documentation reflects that reading, and a command-prefix-only form is not documented as
    covering the `autoUpdate` arm, because it does not.
17. **AC17 — the rollback is written down.** The new ADR states that re-adding the `version`
    key is the rollback, and cites upstream #79950 as the reason the comparator may change.
18. **AC18 — PA-32 §(f) is amended** to name the marketplace clone as a distinct automated
    clone-generating channel. **The count clause is deleted, and this is the most serious defect
    plan review caught.** An earlier draft asserted "81 committed digests, not 80" and would have
    written that correction into the Art. 30 legal register. It is false: `ls -1
    knowledge-base/support/community/*.md | wc -l` returns **80**, and the 81st directory entry
    is `user-conversations/` — a **subdirectory**, counted as a digest. The register is accurate
    and was never stale. The number came from a subagent report and was propagated without
    running the count. **Amend §(f) for the clone channel only; change no figure.**
19. **AC19 — the recovery path reaches a surface the operator digest harvests.** An
    `action-required`-labelled issue carries the remove → re-add → reinstall sequence, and the
    PR title states the user-visible outcome rather than reading as a chore.
20. **AC20 — the full suite is green** via the repo's own invocation, not a hand-enumerated
    subset of paths.

#### Added by the UC-1 resolution (Phase 0.0 and Phase 1B)

26. **AC26 — the `git-subdir` premise was measured, and the number is in the PR body.** Phase
    0.0's two `du -sb` byte counts are recorded, their sum is **< 52,428,800 B (50 MiB)**, and
    both CLI commands completed with `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS` **unset**. If the gate
    was not run, AC26 fails — it is not waivable, because every AC below it and the `closes:`
    frontmatter rest on it. If the gate *ran and failed*, the run halted and this PR does not
    exist in its current form.
27. **AC27 — the new marketplace repo exists, is public, and its name and visibility were
    confirmed by the operator** rather than chosen by the run. The confirmation is recorded in
    the PR body. Public is not a preference: `claude plugin marketplace add` cannot read a
    private source unauthenticated, so a private repo means F does not function.
28. **AC28 — the third manifest is keyless and points where it claims.** In the new repo,
    `jq '.plugins[0]|has("version")'` returns `false`, `jq -r '.plugins[0].source.source'`
    returns `git-subdir`, and `jq -r '.plugins[0].source.path'` returns `plugins/soleur`.
    **Asserted by reading the published file, not the local draft** — it lives outside this tree,
    so no CI check in this repo can reach it and AC12's `--check` gate does not cover it.
29. **AC29 — a real install through the new marketplace resolves and runs.** On a clean `HOME`:
    `marketplace add` then `install soleur@<new marketplace> --scope project` succeeds, and the
    resolved `installPath` is **recorded verbatim** — the third path segment under a `git-subdir`
    source is unverified until this run, and Phase 2.5's ADR-178 amendment consumes the measured
    string, not the inferred one. Read the entry as an **array** of per-scope records selected by
    scope + `projectPath`; `.plugins["soleur@…"]` is not an object (plan review finding 4).
30. **AC30 — the plugin-ID sweep is complete and decided.** The four measured `soleur@soleur`
    sites each carry a recorded decision (migrate / stay, with the reason). `git grep -n
    'soleur@soleur'` over `.github/` and `plugins/soleur/skills/` returns only sites the table
    accounts for. **And `operator-digest-workflow.test.sh` no longer matches on a prefix** — the
    assertion pins the full repo path, so it cannot pass vacuously against
    `jikig-ai/soleur-<anything>`.
31. **AC31 — the existing install's migration route is documented and never clones the
    monorepo.** The published sequence contains no `marketplace add jikig-ai/soleur` step,
    carries `--scope project` on every command, and includes the CLI restart. This is the clause
    that makes `closes: 7471` honest; if the documented route still passes through the 181 MiB
    clone, the frontmatter is wrong and reverts to `refs:`.

### Post-merge

21. **AC21 — the release fired.** `version-bump-and-release.yml` succeeded for the merge commit
    and a new `vX.Y.Z` GitHub Release exists. (The release notes will describe a
    version-*removal* under a `vX.Y.Z` tag; the PR body says why that is not a contradiction —
    tags remain the version, the manifest copy was the vestige.)
22. **AC22 — the migration delivered itself on the first update.** Because the recorded
    `0.0.0-dev` and the manifest-derived `unknown` are unequal, the first `plugin update` after
    the new manifest lands is applied. Verified by reading `installed_plugins.json` before and
    after: `version` moves `0.0.0-dev` → `unknown` and `installPath` is rewritten.
23. **AC23 — the one-time orphan is recorded, not discovered.** The superseded
    `~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/` directory is confirmed present and inert
    (the `installPath` in `installed_plugins.json` points at the new location), and the ADR's
    consequences already say this happens once per existing install.
24. **AC24 — delivery is demonstrated end to end, on content.** After the update, a file the
    merge commit changed is present **with its new content** inside the resolved `installPath`.
    That is the assertion. `gitCommitSha` is recorded as **explicitly-unreliable secondary
    context**, not as a pass/fail clause — plan review finding 5 measured the metadata failing to
    follow the content (upstream #76882, in this plan's own defect corpus), so a
    `gitCommitSha == merge commit` clause can be false after a *successful* delivery. The skill
    count is likewise advisory: a proxy with no stated tolerance, already true before the fix
    ships (96 == 96, measured), and an unrelated in-flight merge could make 95-vs-96 fail a
    correct delivery. Read `installed_plugins.json`'s entry as an **array**, selecting by scope +
    `projectPath`. Every command carries `--scope project`. This is the acceptance criterion the
    predecessor issue could not write; if it cannot be satisfied, the plan did not solve the
    problem it was written for.
    **Run it twice — once per marketplace**, because there are now two live delivery paths:
    through `soleur@<new marketplace>` (the documented path, and the one `closes: 7471` rests on)
    and through `soleur@soleur` (the retained path, which must still work — additive means
    additive).
25. **AC25 — the affected user was told, and told what to do.** Outbound to alpha tester #1 is
    tracked as a follow-through item per `wg-pm-class-followthrough-for-operator-dogfood` — not a
    line in the ship message (`hr-ship-message-no-operator-checklist`). No automated surface
    reaches an external installed user, which is why this is tracked rather than assumed.
    **Scope widened by Phase 1B:** the outbound now carries the migration sequence (1B.6), not
    just a notification, because the existing install does not move to the new marketplace on its
    own. At a population of one this is the entire migration mechanism.
32. **AC32 — the new delivery path is measured post-merge, not just pre-merge.** A fresh install
    from the published marketplace materialises **< 50 MiB** (the same threshold Phase 0.0 used,
    now against the real repo rather than the scratch fixture) and completes with the default
    timeout. A pre-merge fixture passing and the shipped article failing is exactly the gap
    between "measured" and "delivered" this whole plan is about.
33. **AC33 — the old path still works.** `soleur@soleur` remains installable and updatable.
    Additive was the basis of the operator's decision; a change that quietly broke the old entry
    would be outcome (b) in name only.

## Architecture Decision (ADR/C4)

Detection fired: this plan **reverses a recorded decision** (ADR-017's version-field clause),
falsifies a second one's consequences (ADR-178's cache-path reasoning), and — under the UC-1
resolution — **changes the distribution architecture**, which is a decision in its own right and
not a consequence of the first two. All records are deliverables of this plan, not follow-ups
(`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

- **New — one ADR, referred to by slug; ordinal assigned at file-creation time.** *Plugin
  delivery: identity by commit SHA, distribution by a dedicated `git-subdir` marketplace source.*
  Two coupled decisions in one record because they are one delivery architecture — full body in
  Phase 4.2. It declares **partial supersession** of ADR-017's version-field clause only, and
  amends ADR-178's cache-path consequences. Authored via `/soleur:architecture`. **Do not
  pre-claim the ordinal across `origin/*` refs** — plan review cut that ritual as invented
  coordination overhead; assigning at creation time removes the re-derivation and the
  sweep-every-AC-that-names-it step along with it.
- **Amend — ADR-017.** Do **not** silently rewrite its `## Decision` line: that erases why the
  sentinel existed and leaves the 2026-03-03 brainstorm's rejected-options table dangling. Amend
  with the correction plus the alternatives entry; keep `status: active`.
- **Amend — ADR-178.** The cache-path passage and the "name never changes" sentence, anchored on
  **content, not line numbers** (`cq-cite-content-anchor-not-line-number` — the earlier "lines 38
  and 224" citation is exactly what that rule forbids). Reconciled against the **new plugin ID**,
  not merely against the keyless manifest — see the three-column table in Phase 2.5. ADR-178 has
  no `status:` key; it uses `- **Status:** Accepted`.

### C4 views

Enumerated against **all three** `.c4` files, read in full — not grepped for the feature's own
noun, because the missing elements are named for the *actors and systems*, not for "delivery".
The full enumeration and the required edits are in Phase 4.3: the installed-user actor, the
local marketplace-checkout / plugin-cache store, and the GitHub→CLI delivery relationship are
all absent, and the `plugin` system's own description already presumes an element that does not
exist. Both endpoints of every new edge go into the `context` view's `include` list (the `#7332`
note in `views.c4`), then `c4-code-syntax.test.ts` + `c4-render.test.ts` must pass.

### Sequencing

The ADR describes the target state and is true the moment Phase 1 merges — there is no soak or
later slice to wait on, so no `status: adopting` staging is needed. The C4 edit lands in the same
PR; the recorded architecture must not lag the change that creates it.

**Open risk — RESOLVED 2026-08-12, and the resolution is the reason this section changed.** The
risk was that Phases 2 and 4 would produce exactly the artifacts a later change of delivery
*shape* would rewrite: five governance sites naming the current cache path, a new ADR describing
the current identity mechanism, and the first-ever C4 model of the current delivery path. The
advisor consult's recommendation was to settle it **before** Phases 2 and 4, not after.

It was settled. **UC-1 resolved as outcome (b)** — see the RESOLVED status block in
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/decision-challenges.md`.
Phases 2 and 4 are re-scoped to describe the final shape once, and Phase 1B builds it. Nothing
here is written twice; the residual risk is not "we may rewrite this" but "Phase 0.0 may refute
the premise", which has its own halt.

## Test Scenarios

| Scenario | Expected |
|---|---|
| Both manifests keyless, second commit lands on the source | Recorded `gitCommitSha` advances; the update is applied |
| `plugin.json` keyless but `marketplace.json` still versioned | The marketplace entry supplies the version and the no-op returns. Guards against a half-applied Phase 1 — this is the regression AC1's two-sided assertion exists to catch |
| Docs build with `SOLEUR_DOCS_OFFLINE=1` | `softwareVersion` well-formed or absent; never `undefined` |
| Docs build online with at least one published release | `softwareVersion` equals the latest non-draft tag minus its `v` prefix |
| A future PR reintroduces a `version` key | The AC12 CI check fails the PR |
| Marketplace refresh **of the old entry** on a slow link without the env var | Still times out — this plan does not claim otherwise. The documented answer is now *migrate to the new marketplace*, with the timeout setting as the fallback for anyone who cannot |
| **`git-subdir` install on a clean `HOME`, default timeout** | Completes; materialised bytes < 50 MiB. **This is Phase 0.0 and it is a halt gate, not a test** — listed here so the scenario table and the gate cannot drift apart |
| New marketplace entry, plugin manifest keyless, second commit lands on `jikig-ai/soleur` | Recorded `gitCommitSha` advances and the new content appears in `installPath`. Confirms the SHA fallback holds under a `git-subdir` source, which the control group does **not** cover — it is a `github` marketplace with relative `./plugins/<name>` entries |
| New marketplace entry that *does* declare a `version` | The comparator short-circuits again — defect 1, relocated. This is the regression AC28 exists to catch, and the reason the new manifest is keyless too |
| `git-subdir` `path` pointing at a directory that does not exist | Install fails loudly. Verify it fails rather than silently delivering an empty plugin: an empty-but-successful install is the "indistinguishable from success" shape this whole issue is about |
| An existing `soleur@soleur` install after the new marketplace is published | Unaffected — still installed, still updatable. Additive means the old entry keeps working (AC33) |
| Both marketplaces installed simultaneously, same project scope | Two entries, two caches, both resolvable. Record which one the session loads; if it is ambiguous, the migration sequence must uninstall the old before adding the new, not after |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The SHA fallback does not fire for a *relative-path* plugin source, only for `github`/`git-subdir` ones | Phase 0.2 is the probe, and Phase 0.4 is an explicit halt. The control group's entries are relative-path sources (`./plugins/pr-review-toolkit`), which is the evidence that it does — but evidence is not the same as having run it here |
| The migration strands the old `0.0.0-dev/` cache directory forever (#71074 — no pruning) | Real and unavoidable on this route; ~9.5 MiB per install, once. Recorded in the ADR's consequences rather than discovered later. The alternative (option B) strands one per *release* |
| A user mid-migration holds both the old versioned cache and the new keyless one, and the CLI resolves the wrong one | Enumerate in Phase 0.3 and state the resolution order observed. If it resolves to the stale directory, option A needs a migration note before it ships |
| Removing the version key breaks a consumer no grep found | Two consumers were found by grep (`docs/_data/plugin.js`, `docs/_includes/base.njk`) and one by reading (`session-rules-loader.sh` reads `mcpServers`, not `version`). The `--check` gate in AC12 plus the full suite in AC20 are the backstop |
| The stopgap README entry becomes permanent | AC14 requires it to link its own tracking issue — now the old-marketplace-deprecation issue, since the option F issue no longer exists |
| **`git-subdir` does not avoid the full clone, and the premise was doc-sourced** | **Phase 0.0, at the front of the plan, with a numeric halt.** This is the amendment's largest risk and the reason the gate exists rather than a mitigation bolted on afterwards |
| The new marketplace repo drifts from this one — its manifest is edited, a `version` key returns, or the `git-subdir` path stops matching | **No CI check in this repo can reach a file in another repo.** AC28 asserts it at merge time and the canary is the only continuous observer. Stated as a known blind spot; the mitigation is to keep the repo small enough that drift is visible, not to pretend a gate covers it |
| The new repo's name makes `jikig-ai/soleur` a substring, so `operator-digest-workflow.test.sh` passes whether or not the migration happened | Measured in Phase 0.9 and fixed in 1B.7: pin the assertion to the full repo path. Same vacuously-true-assertion class plan review caught in AC6 |
| Two marketplaces, two plugin IDs, and a user who ends up with both | Test Scenarios covers the simultaneous-install case; 1B.6's sequence is ordered so the outcome is deterministic. The cost is recorded in the ADR's `## Consequences` rather than discovered by a user |
| The operator is asked to confirm a repo name mid-run and the run stalls waiting | 1B.1 is the **first** step of Phase 1B and gated only on 0.0, so the confirmation is requested early, while other phases can proceed. Provisioning goes through `/soleur:provision-github`, not a hand-run checklist |
| `closes: 7471` is claimed and the existing install still cannot get the fix | AC31 asserts the documented migration route contains no monorepo clone. If it does, the frontmatter is wrong and reverts — the condition is written down rather than left to judgement at merge time |
| `wg-never-bump-version-files-in-feature` is weakened by the edit | The gate's *behaviour* is unchanged — feature branches still must not introduce a version. Only the clause describing a field that no longer exists is removed. AC7 pins the id and the budget |

## Plan Review — Consolidated

Panel: `dhh-rails-reviewer`, `code-simplicity-reviewer`, `kieran-rails-reviewer`,
`architecture-strategist`, `spec-flow-analyzer` (escalated to 5 by the `single-user incident`
threshold), plus the relevance-gated named panel (`ux-design-lead` and `cmo`, forced active by
the mechanical UI-surface scan hitting two `.njk` files). `cpo` and `cto` reviewed at Phase 2.5
and their findings are already folded in above rather than re-spawned.

### Applied — Mechanical

| Finding | Source | Disposition |
|---|---|---|
| **P5 was logically unearnable.** "Completes inside the CLI's *default* timeout" cannot be bought by *raising* the timeout, yet option E was scored "P5, partially" | code-simplicity | Split into P5a/P5b. E buys P5a and none of P5b; only F buys P5b |
| **P6 was missing.** The recovery sequence — the only thing that helps the one currently broken install — mapped to no property, leaving it formally less justified than the C4 work | code-simplicity | P6 added |
| **AC6 was vacuously true.** `git grep '0\.0\.0-dev'` over `AGENTS.rules.md` returns nothing *today*, because the rule says "frozen sentinel" without the literal. The sweep was blind to the always-loaded rule that is the whole point of Phase 2.1 | DHH + code-simplicity (both) | AC6 split into a literal grep and a paraphrase grep |
| **AC6's allow-list was incomplete** — it named only `archive/` paths, but the literal also lives in 7 non-archive `plans/` files and a non-archive `specs/feat-tag-only-versioning/` | self, by running it | Allow-list corrected against measured output |
| **`autoUpdate: false` was never considered** — the cheapest mitigation for the arm that actually destroyed the checkout, absent from the alternatives table, the cut list, and Phase 3 | DHH | Added as option I, with its measured limit (no CLI flag exposes it) |
| **Option F's core premise is unmeasured** — that `git-subdir` avoids the full clone is doc-sourced, never measured | DHH | Deferral reason restated as epistemic; measuring it is task 1 of the follow-up |
| **The Observability probe carried a dead clause** (`(input_filename|test(...)|not) or true`) | self, by running it | Simplified; measured on the unfixed tree (exit 1, `false`) |
| **AC24's skill-count comparison has no tolerance** and is a redundant proxy | code-simplicity | `gitCommitSha == merge commit` is the assertion; skill count is advisory |
| **The ADR ordinal ritual invents coordination overhead** — pre-claiming across 64 refs, re-deriving in the merge window, sweeping every AC that names it | DHH + code-simplicity (both) | Refer to the ADR by slug; assign the ordinal at file-creation time |

### Applied — a retrieval failure worth more than the finding

DHH found that the `jsonLdSafe(undefined)` throw **was already a recorded institutional
learning** — `knowledge-base/project/learnings/2026-06-01-jsonld-escaping-fixture-symlinks-real-blog-post-njk.md`
states it outright, in the context of a fixture stub whose missing `site.author.knowsAbout` made
`jsonLdSafe(undefined)` throw on `.replace`. Verified: the file exists and says exactly that.

This plan's learnings pass returned three learnings and missed that one. CTO review then
rediscovered the same fact by execution, and this plan wrote a Sharp Edge preaching "run the
filter on that value" as though it were a new insight. **The compounding loop has a retrieval
problem, not a capture problem** — the lesson was on the shelf and the search did not reach it.
That is the more durable finding, and it is recorded here rather than in the Sharp Edge, which
now cites the prior learning instead of claiming discovery.

### Applied — Correctness panel (architecture-strategist + spec-flow-analyzer)

Both correctness reviewers converged independently on the two findings that change this PR's
shape. Where they and the simplification panel agree, the change is applied here.

**1. This PR does not buy P1, and `closes: 7471` was therefore the defect it is fixing.**
P1 ("an installed user who runs the documented upgrade path ends up running current code")
requires the marketplace checkout to advance, which requires a refresh to complete — that is
P5, which is deferred. Option A buys **P2 and P3**; P1 is *conditional* on P5. Closing #7471 on
a PR that cannot deliver P1 to anyone would be reporting success while delivering nothing —
precisely the failure class this issue is about. **Frontmatter changed from `closes: 7471` to
`refs: 7471`; the option F issue becomes the closer.** The alternatives table's option A row
should be read as P2/P3 only.

> **Superseded 2026-08-12 by the UC-1 resolution — the finding was correct and its premise
> changed.** The reasoning above is sound *given a deferred P5*. Outcome (b) undefers P5: option
> F ships as Phase 1B, so this PR buys P1 and P5b directly and there is no option F issue left to
> be the closer. **Frontmatter is back to `closes: 7471`**, conditional on Phase 0.0 — see
> `## Amendment 2026-08-12` for the reasoning, including the honest check against the existing
> install, and Phase 0.8 for the revert branch if the gate fires. The finding is left standing
> rather than deleted: it is why the flip had to be argued instead of assumed.

**2. The premise went stale mid-session — re-measured 2026-08-11 19:10.**
This plan was drafted against an 18:02 snapshot in which the marketplace checkout was destroyed.
It is not any more, and the earlier recovery went through the **non-destructive** route (raise
the timeout, then `marketplace update`) — not the destructive `remove → re-add → reinstall`
sequence this plan prescribes as primary.

| Plan asserted (18:02) | Measured now (19:10) |
|---|---|
| `~/.claude/plugins/marketplaces/soleur/` absent | **Present**, 373 MiB, mtime 19:10 |
| `known_marketplaces.json` points at an absent path | Points at a **present** path |
| Installed cache stale (64 skills vs 96) | Cache **96 skills; repo 96** — identical |
| `soleur.bak` remains | Remains — **374 MiB of orphaned checkout nothing reclaims** |

Consequences applied: Phase 3's "sole route back for the current user" framing is void as
written — the recovery entry is still worth shipping, but for the *next* occurrence, which
`autoUpdate: true` guarantees. **Phase 3.2's primary recovery must be the non-destructive route
that was measured to work**, with `remove → re-add → reinstall` demoted to the fallback for a
genuinely destroyed checkout, plus a `.bak` restore step and the 374 MiB reclaim.

**3. Every command in this plan was scope-blind.** Measured: the install is
`"scope": "project"`, `"projectPath": "/home/jean/git-repositories/skouer/Skouer"`. `claude
plugin update` defaults to `--scope user`. So `claude plugin update soleur@soleur` — the command
in `## User-Brand Impact`, in Phase 3.2, and in AC24 — **targets a scope containing no Soleur
entry**, and will either no-op or create a *second* user-scoped install: two caches, one stale,
no signal which is loaded. The CLI-verification gate ran `--help`, recorded the `--scope` flag,
and stopped one question short of asking what scope the install is in. **Every command and AC
gains an explicit `--scope`.**

**4. `.plugins["soleur@soleur"]` is a JSON array of per-scope entries, not an object.** Measured:
`type: array`. AC22 and AC24 read it as a scalar; written as specified they return `null` and
cannot fail correctly. **Assertions must select the entry by scope + `projectPath`.**

**5. The post-merge ACs were built on a field upstream says is unreliable — and this plan
catalogued that issue itself.** Measured now: recorded `gitCommitSha` `98ad03aa` and
`lastUpdated` `16:43:42`, while the cache *content* is from 18:43 and carries 96 skills matching
a newer tree. **The metadata did not follow the content** — upstream **#76882**, listed in this
plan's own defect corpus. So AC24's `gitCommitSha == merge commit` clause **can be false after a
successful delivery**. Re-anchor AC22/AC24 on **content** (a file the merge commit changed,
present with its new content inside `installPath`) and keep metadata as an explicitly-unreliable
secondary.

**6. AC24's skill-count clause is already true before the fix ships** (96 == 96, measured). A
criterion the pre-change state satisfies measures nothing. Already demoted to advisory; now
replaced outright by a content anchor per `cq-assert-anchor-not-bare-token`.

**7. `claude plugin update --help` says "(restart required to apply)".** No phase, AC, or doc
surface mentioned a restart. Someone who runs the recovery, sees no change, and concludes it
failed hits this plan's own "indistinguishable from success" failure, inverted. **Added to the
recovery sequence.**

**8. The C4 phase would have turned CI red, in the identical shape to the `plugin.js` defect.**
`knowledge-base/engineering/architecture/diagrams/model.likec4.json` (801 KB) is a **committed
render artifact**, and `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs a fresh render
against it. Any `.c4` edit without running `scripts/regenerate-c4-model.sh` fails it. **Added to
Files to Edit with the regeneration step.** Worse, **AC11 named two tests that cannot fail on
this**: `c4-code-syntax.test.ts` is a CodeMirror tokenizer unit test that never reads a `.c4`
file, and `c4-render.test.ts` fully mocks `spawn`/`fs` — its "Could not resolve reference" string
is a *fixture*. AC11 would have passed over a broken model. **The real gate is
`c4-model-freshness.test.sh`.** Also: `platform.plugin` is not in the `context` view's include
list, so a delivery edge terminating there needs it added, or it renders as the disconnected box
the `#7332` note warns about.

**9. The stated rollback is a trapdoor.** "Re-add the key" is a *source-side* edit whose delivery
is gated on the same broken refresh it is rolling back. If upstream #79950 changes keyless
semantics, the repo lands back in a silent no-op **and the corrective edit cannot arrive**. The
real floor is `remove → re-add → reinstall`, which materialises HEAD unconditionally. **The ADR
must say that.**

**10. Internal contradiction on the ADR verb.** Phase 4.1 says "an amendment, not a supersession";
`## Architecture Decision` says the new ADR "supersedes ADR-017's version-field clause". Resolved:
ADR-017 stays `active` and gains a dated `## Amendment (2026-08-11)` block with a forward pointer;
the new ADR declares partial supersession of the named clause only. **Do not rewrite ADR-017's
`## Decision` in place** — the point-in-time-record rule this plan states in Phase 2.6 applies to
an ADR's Decision section too. Relatedly, **ADR-178 was cited by line number (38, 224), which
`cq-cite-content-anchor-not-line-number` forbids** — re-anchor on content.

**11. A third install path is entirely unassessed.** `README.md` and `plugins/soleur/README.md`
both document `claude plugin install --url https://github.com/jikig-ai/soleur/tree/main/plugins/soleur`
— a **non-marketplace source shape**, on two files this plan already edits. The keyless/SHA
control group was explicitly scoped to a `github` marketplace source with relative
`./plugins/<name>` entries and says nothing about this population. The Non-Goals declined other
surfaces because they name a different *verb*; this is a different *source shape*. **Phase 0
gains a probe:** does a `--url` install record a `gitCommitSha`, is it affected by the deletion,
and does it clone the subtree only — in which case it may already be a partial P5 answer sitting
in the README.

**12. `.claude-plugin/marketplace.json` is not in the release path filter.**
`version-bump-and-release.yml` filters `paths: ['plugins/soleur/**', 'plugin.json']` — and that
root `plugin.json` does not exist. This PR is safe because both edits land in one commit, but a
future marketplace-only correction would ship no tag and no release.

**13. Corroborating evidence the plan missed:** `apps/web-platform/infra/cloud-init-plugin-seed.test.sh`
already seeds `{"name":"soleur-test"}` — a **version-less manifest** — and the mount path passes.
The seeding/mount path is proven tolerant of an absent version key.

### Surfaced — Taste / User-Challenge (not auto-applied)

**Both the simplification panel (DHH + code-simplicity) and the plan's own author fire on the
same scope**, which per this repo's plan-review convention biases toward *delete* rather than
*fix*. The correctness panel's verdict on the same scope is still outstanding at the time of
writing; where the two panels disagree, deepen-plan adjudicates.

- **Cut Phase 4.3 (C4 modelling).** Both simplification reviewers rank it the largest item
  buying zero properties, on the decisive argument that **deleting a manifest key does not change
  the delivery topology** — actor, cache, and edge are identical before and after. The one thing
  genuinely falsified is the `plugin` system's description presuming an element that does not
  exist, and that was already false before this plan. Counter-argument: `wg-architecture-decision-is-a-plan-deliverable`
  makes C4 a plan deliverable. **Proportionate middle, recommended:** fix the one falsified
  description line now; attach the full modelling to option F, which is what actually changes the
  topology. Modelling the current shape now and re-modelling it when F lands is doing it twice.
- **Cut ADR-183, fold its content into ADR-017.** DHH: this change *completes* ADR-017 rather
  than reversing it — "version lives in git tags, not in files" was always the decision, and the
  sentinel was the half-measure. A decision record for "we finally did what we already decided"
  is filing for its own sake. code-simplicity **disagrees** and keeps it as the only home for the
  rollback statement. Unresolved; a genuine split.
- **Reduce both ADR amendments to `Amended by <ADR>` pointers.** code-simplicity notes the plan's
  own Phase 2.6 rule — *"do not rewrite point-in-time records"* — and that an ADR's
  `## Consequences` is precisely that. ADR-178's cited passage narrates the measured defect that
  motivated this plan; rewriting it destroys the record of why the successor exists.
- **Collapse Phase 0's four probes to one migration fixture.** 0.4 strictly contains 0.2; 0.3 is
  a read that 0.4 requires anyway; 0.5 is an unbounded wait no branch is conditional on.
- **Cut AC12** (the CI keyless gate): a fifth mechanism for a property AC1, the retained
  `wg-never-bump-version-files-in-feature`, the ADR, and the Observability probe already buy —
  defending against a hand-edit that has never occurred, on a field whose un-gated sentinel
  survived five months untouched.
- **Cut Phase 1.4** (the new JSON-LD regression test): the plan itself names the two existing CI
  suites that already fail loudly without the guard.
- **Collapse 25 ACs to roughly 8.** DHH's LARP test is the verb: *returns*, *exits*, *equals* are
  post-conditions; *is recorded*, *is stated*, *is tracked*, *reflects* check that a sentence was
  written. AC19 — an acceptance criterion about PR title style — is named as the clearest case.
- **Reduce the stopgap from three surfaces to one** plus the direct outbound, at a population of
  one, since all three must stay in sync when option F changes the install path.

**Disposition:** these are scope decisions against the operator's stated direction and against
mandatory workflow gates, so none is auto-applied. UC-1 in
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/decision-challenges.md`
already carries the related question, and these cuts sharpen it: the C4 and ADR work are exactly
the artifacts that get written twice if option F lands later.

> **Adjudicated 2026-08-12 by the UC-1 resolution.** Option F lands **now**, not later, so the
> "written twice" premise under the two largest cuts is gone. Dispositions:
>
> - **Cut Phase 4.3 (C4) — not carried.** Its decisive argument was that deleting a manifest key
>   does not change the delivery topology. True then; false now. Phase 1B adds an external system,
>   two edges with different payload sizes, and a changed payload boundary. Recorded in Phase 4's
>   re-scope note so this is a reasoned rejection, not a review finding quietly dropped.
> - **Cut ADR-183 / fold into ADR-017 — not carried.** The split was genuine (DHH for folding,
>   code-simplicity against). It resolves against folding: the record now carries a *distribution*
>   decision that ADR-017 never contemplated, so it is not "we finally did what we already
>   decided."
> - **The ordinal ritual, the vacuous AC6 grep, the AC24 tolerance, the P5a/P5b split — all
>   carried and applied**, and they remain applied above. Nothing in this amendment weakens them.
> - **The remaining cuts** (collapse Phase 0's probes, cut AC12, cut Phase 1.4, collapse the ACs,
>   reduce the stopgap surfaces) are untouched by the resolution and stay as surfaced, unapplied
>   taste findings. Note the amendment moves in the opposite direction on one of them: Phase 0
>   gained 0.0 and 0.9 rather than collapsing — deliberately, because both exist to falsify
>   something rather than to be thorough.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled.
- **`marketplace.json` carries two different fields both called `version`.** The top-level one
  (`1.0.0`) is the manifest-format version; `plugins[0].version` is the plugin's. Deleting the
  wrong one breaks the manifest. AC2 exists solely to catch that.
- **`has("version")` and `.version == null` are not the same question.** `jq -r '.version'`
  prints `null` both when the key is absent and when it is present-and-null, and the CLI's
  fallback keys on absence. Every assertion in this plan uses `has("version")` for that reason.
- **A control group is evidence about the control group.** Six official plugins updating on a
  keyless manifest is strong, and it is still not a measurement of Soleur's own source shape.
  Phase 0.4's halt exists because the temptation to skip 0.2 — the evidence "obviously" being
  sufficient — is exactly how a plan ships a premise instead of a fact.
- **The two defects have asymmetric fixability, and conflating them wastes the PR.** Defect 1 is
  ours and costs two deleted lines. Defect 2 is the CLI's; the only thing this repository
  controls is *what gets cloned*. A plan that treats the issue's four suggestions as four work
  items will spend most of its effort on three that cannot be built here.
- **A JSON-serialising filter does not degrade on `undefined` — it throws**, and **this repo
  already knew that.** `jsonLdSafe` is `JSON.stringify(value).replace(…)`, and
  `JSON.stringify(undefined)` returns the *value* `undefined`, so `.replace` raises. This plan's
  first draft asserted the opposite ("renders a wrong-but-present string"). It was corrected by
  execution — but the fact was already written down, in
  `knowledge-base/project/learnings/2026-06-01-jsonld-escaping-fixture-symlinks-real-blog-post-njk.md`,
  where a fixture stub missing `site.author.knowsAbout` made `jsonLdSafe(undefined)` throw on
  `.replace`. The learnings pass for this plan returned three files and missed that one. **The
  transferable lesson is not "run the filter" — it is that a capture loop with a retrieval gap
  looks exactly like a repo that never learned the thing.** When a plan is about to assert how a
  named helper behaves on a missing value, grep the learnings corpus for the helper's name before
  reasoning about its body.
- **A hermetic-mode flag is not a rare path.** `SOLEUR_DOCS_OFFLINE=1` reads like an escape
  hatch and is in fact set by two CI suites that spawn a full build. The failure it triggers is
  invisible on the production deploy (which has a real release tag) and deterministic in CI —
  the shape that looks like a flake and is not. Grep for who sets a flag before calling its path
  rare.
- **A cut justified by another item's fix is void if that item is deferred.** This plan cut the
  P4 repair "because P5 removes the failure", then deferred P5 — leaving P4 ungated and
  unrepaired, on a marketplace whose `autoUpdate: true` reaches the destructive arm with no user
  action. Any cut whose stated reason is "X will handle it" must be re-checked at the moment X
  moves, and CPO review is where this one was caught.
- **A control group measures the state it is in, not the state you are migrating from.** Six
  keyless plugins updating correctly is evidence about installs that were *born* keyless. Every
  existing Soleur install is instead a versioned record meeting a keyless manifest — a different
  transition, unmeasured until Phase 0.4 was added. The tell: the evidence and the population
  are described by different sentences.
- **A corrected page with a stale JSON-LD twin still ships the old claim.** `changelog.njk`
  carries its upgrade FAQ twice — once as rendered copy, once inside a `FAQPage` block fed to
  answer engines. Fixing only the visible half leaves the machine-readable assertion standing,
  which on an AEO-optimised site is the half that travels further.
- **Removing the version key is not a version-management change.** ADR-017 said version lives in
  git tags, not in files; the sentinel was the half-measure that kept a vestigial file-side copy
  alive. Anyone reading this as "Soleur abandoned tag-based versioning" has it backwards, which
  is why AC9 requires the amendment to say so in ADR-017 itself.
- **A repo name can make an assertion vacuous.**
  `plugins/soleur/test/operator-digest-workflow.test.sh` asserts
  `plugin_marketplaces:.*jikig-ai/soleur`. Name the new marketplace repo `soleur-marketplace` and
  `jikig-ai/soleur` is a **substring** of `jikig-ai/soleur-marketplace`, so the test passes
  identically before and after the migration it is supposed to police. This is the third
  vacuously-true assertion this plan has caught, after AC6's literal grep and AC24's
  already-satisfied skill count. The tell is the same each time: the assertion matches a
  *fragment* of the thing it means to pin.
- **"~50 KB" and "~17 MiB" answer different questions, and only one of them is the payload.** The
  marketplace repo is ~50 KB — that is what `marketplace add` clones. The plugin is materialised
  separately through the `git-subdir` entry and measures ~17 MiB at the floor. A compliance
  argument written against 50 KB would be wrong by 340×, and would be wrong in the direction that
  flatters the plan. Carry both numbers with their referents attached.
- **A gate whose failure mode is "proceed anyway" is not a gate.** Phase 0.0's halt is written to
  stop the run and return the decision to the operator, and it explicitly forbids the tempting
  degradation — quietly shipping Phase 1 + Phase 3 and calling it outcome (a). Outcome (a) is a
  choice the operator can make; it is not a place a run lands by default when a measurement
  disappoints.
- **The marketplace manifest's `name` field, not the repo name, sets the plugin ID.** The cache
  path is `cache/<marketplace name>/<plugin name>/<version>` — read off the measured control-group
  entry, not documentation. So a repo named one thing and a manifest named another silently
  produces a third ID, and every doc surface that named the repo will be wrong.
- **A check in this repo cannot police a file in another repo.** Once the marketplace manifest
  lives in a second repository, AC12's `--check` gate, `git grep`, and every CI job here are blind
  to it. The plan says so rather than implying coverage it does not have — that blind spot is a
  real cost of option F and belongs in the ADR's consequences beside the benefit.
