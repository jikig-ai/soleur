---
title: "fix: plugin delivery path — drop the version sentinel so the updater tracks the commit SHA"
date: 2026-08-11
slug: fix-plugin-delivery-path
branch: feat-one-shot-7471-plugin-delivery-path
issue: 7471
refs: 7471
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

### The delivery paradox (raised by CPO review — the structural finding)

**The fix for defect 1 ships inside the manifest, and seeing the new manifest requires a
marketplace refresh — which is defect 2.** The fix cannot self-deliver by the path it fixes. For
the current install it is worse than gated: the checkout is already gone, so the only route is
remove → re-add → reinstall, and the re-add *is* the 120s clone. This is why Phase 3 is not
optional garnish on Phase 1.

### Population calibration

`knowledge-base/product/roadmap.md` line 81: **Beta users: 1** — alpha tester #1 (Skouer),
onboarded 2026-08-06 **on the self-hosted CLI plugin**. The affected population and the total
population are the same set, which is what makes `single-user incident` the literal, not
rhetorical, threshold. It also relocates the real deadline: the deferred P5 fix becomes
cohort-wide the moment #1439 (recruit 10 founders) resumes — a roadmap dependency currently
recorded nowhere.

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
| "Make marketplace refresh viable … (shallow/partial clone or a raised timeout default)" | Both are Claude Code CLI internals. Nothing in this repository selects the clone strategy or the timeout default | Re-scope to the two levers that are ours: *what* gets cloned (deferred, tracked) and *what the documented command says* (in scope). Record the rest as upstream |
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
| **E. A persistent timeout env setting, documented on the surfaces users actually read** | P5, partially | **Selected as a stopgap — re-scoped twice under review.** Originally "fold the var into the documented one-liner (README only)". CTO: a command prefix sets the var for *one invocation*, but `autoUpdate: true` fires the refresh inside ordinary sessions, so the automatic, higher-frequency, user-invisible arm stays at 120s. It must be a **persistent** setting (an `env` block in `~/.claude/settings.json`, or a shell-profile export), and that route must be verified before it is documented. CPO: README is not where users go — the docs site is |
| F. Publish a small dedicated marketplace source (`git-subdir` back into `jikig-ai/soleur`) | P5 | **Deferred to a tracked, milestone-targeted issue — but the original reason was wrong.** The schema is proven (Anthropic's own marketplace uses `git-subdir` + pinned `ref`/`sha` for 42crunch and adobe). This plan first deferred it as "a breaking change to the documented install path", which holds only if `jikig-ai/soleur` is *replaced* as the marketplace. CTO raised the **additive** shape: a *second* ~50 KB repo whose single entry is a `git-subdir` source. Existing installs keep working; new installs clone 50 KB instead of 181 MiB. That breaks nothing, and costs a new repo plus a plugin-ID change (`soleur@soleur-marketplace`). It is deferred on **scope** grounds, not on breakage. **The strongest deferral reason, added under plan review, is epistemic:** option F rests on a premise this plan never measured — that a `git-subdir` source avoids the full monorepo clone. That is sourced from Anthropic's docs ("clones sparsely to minimise bandwidth for monorepos") and nothing more. If `git-subdir` still fetches the 181 MiB history before resolving the subdirectory, F buys nothing and the second repo is dead weight. **Measuring that premise is task 1 of the follow-up issue, and it may refute F outright.** A plan that lectures itself three times about measuring before asserting should not exempt its own preferred alternative. Contested — the compliance gate and CTO argue for pulling F forward; see UC-1 |
| G. Point the *marketplace* source at a subdirectory of this repo | P5 | **Refuted by the schema.** Marketplace sources are github / git URL / local path / remote JSON URL. `git-subdir` is a *plugin* source, read only after the marketplace clone has already completed. Recorded so it is not re-proposed |
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
observation, not a disclosure; the deferred option F would narrow it to `plugins/soleur/`.

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
- Publishing a dedicated marketplace source (option F) — deferred to a milestone-targeted
  tracking issue, recorded as **contested** (the compliance gate and CTO both argue for pulling
  it forward; CPO accepts the architectural deferral). Plan-review adjudicates.
- Building the operator-side delivery canary — real work with its own failure modes and an
  auth-feasibility gate; tracked separately (Phase 3.5).
- Building an in-session staleness banner (option D) — deferred, trigger named.
- Rewriting the remaining install-command surfaces (`claude-code-plugins.njk`,
  `ai-agents-for-solo-founders.njk`, the blog posts,
  `knowledge-base/marketing/distribution-content/soleur-vs-crewai.md`). Those state
  `claude plugin install soleur`, which is not the failing verb; the two surfaces this plan
  edits are the ones carrying the *marketplace add* command and the false *upgrade* claim. If
  option F lands, all of them change together, which is the right time to touch them once.

## Implementation Phases

### Phase 0 — Falsify the plan before building on it

The whole plan rests on one claim: that a keyless manifest makes the CLI track the commit SHA.
It is measured against a control group, but never against *Soleur's own* install. Phase 0 is
the probe that can end the plan cheaply.

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

0.8 **Halt conditions — each with a defined branch, because a halt with no alternative is a
stall.**

| Probe | Failure | Branch |
|---|---|---|
| 0.2 | The SHA fallback does not fire for a relative-path plugin source | Option A is refuted. Fall back to the alternatives table — and note the surviving candidate is option F, the deferred marketplace source, whose `git-subdir` entry is a *different* source type and may behave differently. That is the alternative; do not stall |
| 0.4 | The migration resolves to the stale `0.0.0-dev/` directory | Option A needs an explicit migration step (uninstall/reinstall guidance) before it ships. Phase 1 does not begin without one |
| 0.6 | The refresh still cannot complete from the migration state with the persistent setting | The stopgap does not deliver, so Phase 1 ships a fix that structurally cannot arrive. Escalate UC-1 in `decision-challenges.md` from a deferral question to a blocking one |
| 0.7 | A version consumer exists outside the known set | Add it to Phase 1 and re-run the sweep |

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

### Phase ordering note — recovery precedes the manifest edit

*(Advisor consult, applied.)* The phase numbering below reads as "fix, then document". That is
backwards for this change. The Phase 1 fix ships **inside** the manifest, and a user sees the new
manifest only through a marketplace refresh — the operation defect 2 breaks. The persistent
timeout setting is therefore **not a Phase 3 stopgap; it is Phase 1's delivery mechanism.**
Phase 3.1 (verify the persistent-env route) and Phase 0.6 (rehearse a real refresh from the
migration state) both gate Phase 1 being *complete*, not merely *merged*. Execution order:
0.1–0.5 → 3.1 → 0.6 → 1 → 2 → 3.2–3.7 → 4 → 5.

### Phase 2 — Reconcile the governance corpus

The sentinel is prose-enforced in **five** places — four instruction sites plus ADR-178, which
CTO review found and this plan's first draft missed. All five now assert something false, and a
rule that is false is worse than no rule.

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

2.5 **`ADR-178` is the fifth site.** It hard-codes the cache path
`~/.claude/plugins/cache/soleur/soleur/0.0.0-dev/` at its line 38, and at line 224 states the
reasoning: *"version `0.0.0-dev`, so the cache directory name never changes and there is no
version bump to trigger an update."* Both become false. ADR-178 merged last week and is
`active` — it is not an archive record, and it needs the amendment.

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

3.4 File the option F follow-up: publish a dedicated marketplace source so the CLI stops cloning
the monorepo. Include the measured size table, the `git-subdir` schema with the 42crunch/adobe
precedent, **the additive-second-repo shape** (which breaks no existing install), the compliance
gate's minimisation and Art. 17 findings, and the migration question. **Target it at the
roadmap Phase 4 milestone and record it as a prerequisite of #1439** (recruit 10 founders) —
today that dependency is recorded nowhere, and the deferral will otherwise age into the next
recruitment push. Passes the `wg-defer-only-after-inline-triage` triple test: not a ten-line
change, observable trigger, fires well inside six months.

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

4.1 Amend `ADR-017`. Its `## Decision` names the sentinel and its `## Consequences` claims
"zero manual version management" — the first is now wrong and the second was always true for
the wrong reason. Add the correction plus an `## Alternatives Considered` entry recording why
the CI write-back stays rejected (the CLA-ruleset constraint is unchanged). ADR-017 keeps
`status: active`; this is an amendment, not a supersession.

4.2 Write the new ADR for the delivery decision itself: version identity for an installed
plugin is the source commit SHA, obtained by omitting the field rather than by publishing a
string. Provisional ordinal **ADR-183** — verified free across all 64 `origin/*` refs on
2026-08-11 (179–182 are already claimed on sibling branches). The ordinal is a claim, not a
reservation: re-derive it against a freshly fetched `origin/main` immediately before merge, and
if it moves, sweep this plan, the tasks file, and any AC naming the ordinal in the same edit.

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

Add the actor, the local cache store, and the delivery relationship; tag the external ones
`#external`; and add both endpoints of every new edge to the `context` view's `include` list —
per the `#7332` note already in `views.c4`, an edge renders only when *both* endpoints are
included, and a node added to a view containing neither endpoint renders as a disconnected box.
Then run `apps/web-platform/test/c4-code-syntax.test.ts` and `c4-render.test.ts`; a `view
include` naming an undefined element fails there, never at `tsc`.

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
| `knowledge-base/engineering/architecture/diagrams/views.c4` | Add both endpoints of each new edge to `context` |

## Files to Create

| File | Purpose |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-183-*.md` | The delivery-identity decision (ordinal provisional) |
| `knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/tasks.md` | Task breakdown |

**Glob verification.** Every path above was confirmed to exist with `git ls-files` /`ls` at plan
time except the two Files-to-Create entries. `plugins/soleur/plugin.json` — the path the issue
cites — was confirmed **not** to exist and is deliberately absent from this table.

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
| The whole-repo clone industrialises the Art. 17 erasure impossibility PA-32 §(f) already records — converting a bounded, counted population (2 forks) into an unbounded population of full-history clones | Art. 17; Art. 5(1)(e) | Important | **Yes.** Options F/(remote-URL) remove the corpus *and* the 181 MiB history from the payload; the stopgap-only path preserves the fan-out |
| Minimisation: **887 of 13,523 delivered files (~93%) and ~94% of bytes are not the product**, including `knowledge-base/legal/` (the Art. 30 register itself, plus 41 counsel-review memoranda) and 333 design screenshots | Art. 5(1)(c); **Art. 25(2)** | Important | **Yes.** Art. 25(2) is the sharper citation: "already public on GitHub" answers a *disclosure* question, not a *minimisation* one. Retrievable-on-request and pushed-to-every-installer are different operations |
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

**Effect on this plan.** Finding 1 and finding 2 are a substantive argument that option F is
not merely an engineering nicety to defer but the option with the compliance case behind it,
and they are recorded as a **contested deferral** in the Domain Review below rather than
absorbed. The gate also confirms that **item 1 (removing the `version` key) has zero GDPR
surface on its own** and could ship without any compliance gate — which is independent support
for the split this plan proposes.

**Register work carried by whichever option lands:** amend PA-32 §(f) to name the marketplace
clone as a distinct automated clone-generating channel (its counts are stale in this branch
already — 81 committed digests, not 80), and if option F lands, add the new repository to the
register's in-scope surfaces list and widen the `GitHub Inc` vendor-row scope cell, which
currently reads "cc-router in-process MCP tool surface" and does not cover distribution
hosting.

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
end to end** and asserts `installed_plugins.json → soleur@soleur.gitCommitSha == origin/main`.
This is the layer-7 analogue of `scripts/prod-version-drift-check.sh` (#7091) — already cited
in this plan as the staleness-detector precedent, here extended rather than re-invented. Adopt
its four-verdict discipline, and in particular its stated rule: **a clone timeout must report
`CHECK_ERROR`, never `CLEAN`** — "we could not evaluate" must never be encoded as "no drift".

**It would have caught both defects before a user did.** That is the argument for building it.

**First task is a feasibility gate, not construction:** determine whether `claude plugin
marketplace add / install / update` function unauthenticated on a runner. If they require
credentials, the canary is blocked and the plan says so rather than designing around an
unverified assumption.

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
10. **AC10 — the new ADR exists at the ordinal this plan names,** and that ordinal was
    re-derived against a freshly fetched `origin/main` within the merge window. If it moved,
    `grep -rn 'ADR-<old>' knowledge-base/project/{plans,specs}/` returns zero.
11. **AC11 — the C4 delivery path renders.** `model.c4` declares the installed-user actor, the
    local plugin-cache store, and the GitHub→CLI delivery relationship; `views.c4`'s `context`
    view includes **both** endpoints of each new edge; and
    `apps/web-platform/test/c4-code-syntax.test.ts` plus `c4-render.test.ts` pass.
12. **AC12 — a CI check now asserts the manifests stay keyless,** following the repo's
    established `--check` shape rather than a write-back, so the defect cannot silently return.
13. **AC13 — the deferrals are tracked, and the load-bearing one is milestone-targeted.** The
    option F issue exists, carries the measured size table and the additive-second-repo shape,
    is targeted at the roadmap Phase 4 milestone, and records the blocking relationship to
    #1439. The delivery-canary issue exists with its auth-feasibility check as task 1. The
    in-session banner is an explicit Non-Goal with its trigger stated.
14. **AC14 — the stopgap names its own expiry and is on the surfaces users read.** The entry
    appears in `README.md`, `plugins/soleur/README.md`, and
    `plugins/soleur/docs/pages/getting-started.njk`; it links the option F issue and states that
    it is a workaround for an upstream defect.
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
24. **AC24 — delivery is demonstrated end to end, not asserted.** After a marketplace refresh
    and `claude plugin update soleur@soleur`, `installed_plugins.json` records a `gitCommitSha`
    **equal to the merge commit**. That equality is the assertion; the installed cache's skill
    count is recorded as advisory context, **not** as a pass/fail clause — it is a proxy with no
    stated tolerance, and an unrelated in-flight merge could make 95-vs-96 fail a correct
    delivery. This is the acceptance criterion the predecessor issue could not write; if it
    cannot be satisfied, the plan did not solve the problem it was written for.
25. **AC25 — the affected user was told.** Outbound to alpha tester #1 is tracked as a
    follow-through item per `wg-pm-class-followthrough-for-operator-dogfood` — not a line in the
    ship message (`hr-ship-message-no-operator-checklist`). No automated surface reaches an
    external installed user, which is why this is tracked rather than assumed.

## Architecture Decision (ADR/C4)

Detection fired: this plan **reverses a recorded decision** (ADR-017's version-field clause) and
falsifies a second one's consequences (ADR-178's cache-path reasoning). Both records are
deliverables of this plan, not follow-ups (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

- **New — ADR-183 (provisional ordinal):** *Track plugin identity by git commit SHA, not by a
  manifest version field.* Supersedes ADR-017's version-field clause and amends ADR-178's
  cache-path consequences. Its `## Consequences` is the natural home for the two risks that have
  nowhere else to live: dependence on undocumented CLI internals (≥3 recording modes, upstream
  #79950 actively changing the comparator) and the stated rollback (re-add the key). Authored via
  `/soleur:architecture`. **The ordinal is a claim, not a reservation** — 179–182 are already
  claimed on sibling `origin/*` branches, 183 was free across all 64 refs on 2026-08-11, and it
  must be re-derived against a freshly fetched `origin/main` immediately before merge. If it
  moves, sweep this plan, `tasks.md`, and every AC naming it in the same edit.
- **Amend — ADR-017.** Do **not** silently rewrite its `## Decision` line: that erases why the
  sentinel existed and leaves the 2026-03-03 brainstorm's rejected-options table dangling. Amend
  with the correction plus the alternatives entry; keep `status: active`.
- **Amend — ADR-178.** Lines 38 and 224 (cache path and the "name never changes" reasoning).

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

**Open risk, unresolved and deliberately not decided here.** Phases 2 and 4 produce exactly the
artifacts that a later change of delivery *shape* would rewrite: five governance sites naming the
current cache path, a new ADR describing the current identity mechanism, and the first-ever C4
model of the current delivery path. If the deferred marketplace source (option F) lands later,
each is written twice. The advisor consult's recommendation is to settle that question **before**
Phases 2 and 4, not after — either by shipping option F now, or by narrowing these two phases to
claims that stay true under either delivery shape. This is recorded as **UC-1** in
`knowledge-base/project/specs/feat-one-shot-7471-plugin-delivery-path/decision-challenges.md`
and requires an operator decision; it is not settled by this plan.

## Test Scenarios

| Scenario | Expected |
|---|---|
| Both manifests keyless, second commit lands on the source | Recorded `gitCommitSha` advances; the update is applied |
| `plugin.json` keyless but `marketplace.json` still versioned | The marketplace entry supplies the version and the no-op returns. Guards against a half-applied Phase 1 — this is the regression AC1's two-sided assertion exists to catch |
| Docs build with `SOLEUR_DOCS_OFFLINE=1` | `softwareVersion` well-formed or absent; never `undefined` |
| Docs build online with at least one published release | `softwareVersion` equals the latest non-draft tag minus its `v` prefix |
| A future PR reintroduces a `version` key | The AC12 CI check fails the PR |
| Marketplace refresh on a slow link without the env var | Still times out — this plan does not claim otherwise, and the README entry is the documented answer until option F lands |

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The SHA fallback does not fire for a *relative-path* plugin source, only for `github`/`git-subdir` ones | Phase 0.2 is the probe, and Phase 0.4 is an explicit halt. The control group's entries are relative-path sources (`./plugins/pr-review-toolkit`), which is the evidence that it does — but evidence is not the same as having run it here |
| The migration strands the old `0.0.0-dev/` cache directory forever (#71074 — no pruning) | Real and unavoidable on this route; ~9.5 MiB per install, once. Recorded in the ADR's consequences rather than discovered later. The alternative (option B) strands one per *release* |
| A user mid-migration holds both the old versioned cache and the new keyless one, and the CLI resolves the wrong one | Enumerate in Phase 0.3 and state the resolution order observed. If it resolves to the stale directory, option A needs a migration note before it ships |
| Removing the version key breaks a consumer no grep found | Two consumers were found by grep (`docs/_data/plugin.js`, `docs/_includes/base.njk`) and one by reading (`session-rules-loader.sh` reads `mcpServers`, not `version`). The `--check` gate in AC12 plus the full suite in AC20 are the backstop |
| The stopgap README entry becomes permanent | AC14 requires it to link its own tracking issue; the option F trigger is observable |
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
