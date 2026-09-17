---
title: "fix: remove duplicate /soleur:go, /soleur:help, /soleur:sync slash-menu entries"
date: 2026-09-17
slug: fix-duplicate-soleur-slash-command-entries
branch: feat-one-shot-dedupe-harness-shim-skills
lane: cross-domain
type: fix
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
---

## Overview

Three names — `go`, `help`, `sync` — exist both as plugin commands
(`plugins/soleur/commands/<name>.md`) and as plugin skills
(`plugins/soleur/skills/<name>/SKILL.md`). Claude Code loads plugin commands and plugin
skills into the same slash menu, so each of the three renders twice, carrying two
different descriptions. `qa` exists only as a skill and renders once — the control that
confirms the mechanism.

The three colliding skill directories are thin wrappers added on 2026-09-11 by
`de2e50463` to give the **Devin CLI** an entry point, because Devin loads slash commands
from `skills/` and not from `commands/`. One commit later, `c99eeebe1` added the proper
per-harness location at `plugins/soleur/devin/skills/`, which superseded them without
removing them.

**This plan adds `user-invocable: false` to those three shims** — a documented Claude Code
frontmatter key that removes a skill from the `/` menu while leaving it invocable by the
model — **and adds a mechanical guard so the collision class cannot recur.** Nothing is
deleted and no harness adapter code changes.

Deleting them outright was the original choice and is still the eventual end state, but
review established that it would remove `Skill(soleur:go)`, which
`apps/web-platform/server/prompt-injection-wrap.ts:25` dispatches on **every** Command
Center message, and would delete the only Devin skills root ever measured to load. See
`## Decision` — that section is the one to read first.

Note: `lane:` could not be carried forward — no `spec.md` exists for this branch, so it
defaults to `cross-domain` (TR2 fail-closed). The Phase 2.5 domain sweep independently
found no relevant business domain; see `## Domain Review`.

## Research Reconciliation — Spec vs. Codebase

The task brief supplied twelve numbered facts. Every one was re-verified on disk in this
worktree. Ten held. **The brief's stated crux was falsified, and its count was off by one.**

| Brief claim | Reality on disk | Plan response |
|---|---|---|
| **CRUX: "Simply deleting `skills/{go,help,sync}/` WOULD BREAK GROK BUILD."** | **False.** Grok harness support landed 2026-07-10/11 (`3598693f4`, `.grok/config.toml`, #6314; `766199eda`, the harness adapter). The three shims landed 2026-09-11 (`de2e50463`). Grok's `/go`, `/help`, `/sync` worked for two months with no `skills/go/` on disk. | Option (a) is unnecessary. Adopt (a′): delete only. |
| "`harness.ts` grok branch emits `skills/${name}/SKILL.md`, so Grok resolves `/go` there." | The template exists (`harness.ts:174`), but `invokeSkill()` has exactly one production caller — `go-routing.ts:59`, passing `target.skill` from `GO_SKILL_ROUTES` (`workflow-fidelity.ts:89-97`), whose values are `one-shot`, `drain-labeled-backlog`, `drain-prs`, `review`, `incident`, `brainstorm`. `go`/`help`/`sync` are **never** routing targets. The interpolation is never evaluated with those three names. | `harness.ts` needs **no change**. |
| "The three shims are shared harness wrappers." | All three self-identify as Devin-only in their own H1 and body: `# /soleur:go (Devin CLI entry point)` / "You are the `/soleur:go` slash command for the Soleur plugin on **Devin CLI**." Zero Grok content. `de2e50463`'s commit message gives Devin installation as the reason; its `harness.ts` diff touches **only** the `devin` branches — the `grok` branch is untouched. | Confirms they are misplaced Devin artifacts. |
| "Option (b) may work if `.claude-plugin/plugin.json` honors a `skills` allowlist/denylist." | **Refuted.** Claude Code's `skills` manifest key exists but is **additive** — the default `skills/` directory is always scanned and listed directories load *alongside* it. There is no denylist and no allowlist. | (b) rejected; see `## Alternatives Considered` for the stronger variant (b′) that does exist. |
| "`components.test.ts:187` may need scoping to exclude per-harness dirs." | Not needed. `test/helpers.ts:22` — `discoverSkills()` = `new Glob("skills/*/SKILL.md").scanSync(PLUGIN_ROOT)`. The per-harness copies live at `plugins/soleur/{codex,devin}/skills/`, which are **siblings of** `plugins/soleur/skills/`, not descendants — so *every* recursive glob in the repo is also safe, because they are all rooted at `plugins/soleur/skills`. | No scoping change. |
| "`plugins/soleur/skills/` contains 98 skills"; the fork framing used "99 → 96". | **98 → 95** is correct. There are 99 *directories*, but `plugins/soleur/skills/flag-bootstrap/` holds only `SETUP.md` and no `SKILL.md`, so every count in the repo keys on `SKILL.md` and reads 98. A plan written against 99 → 96 would produce off-by-one edits that red-line the CI drift gate. | All counts: 98 → 95. Guard derives skill names as *directories containing `SKILL.md`*. |
| Tests likely needing updates: `devin-harness.test.ts`, `harness.test.ts`, `components.test.ts`. | Partly wrong, and it **missed the one test that actually breaks**. `codex-plugin.test.ts:32` / `devin-plugin.test.ts:28` do loop over `["go","help","sync"]` but assert only against `codex/skills/<name>` and `devin/skills/<name>` — unaffected. `harness.test.ts:274-283` and `devin-harness.test.ts` assert only on `routingInstructions()` / `INSTRUCTIONS.md` string content — unaffected. | See next row. |
| (not in brief) | **`plugins/soleur/test/devin-cloud-mode.test.ts:496` asserts `expect(marked.length).toBe(67)` under the comment `// 64 plugin skills + 3 devin shims.`** That suite is the only one in the repo that walks **two roots** (`skills/` *and* `devin/skills/`). `skills/go/SKILL.md` and `skills/sync/SKILL.md` carry the `soleur-cloud-mode` marker; `skills/help/SKILL.md` does not. Deleting them takes the count to 65. A literal grep for `skills/go` does not surface this — the suite enumerates by `readdirSync`. | Update to `65` / `// 62 plugin skills + 3 devin shims.` **This is the only red test.** |
| (not in brief) | `scripts/codex-plugin-smoke.mjs:52-53` walks `skills/` for dirs containing `SKILL.md` and then unconditionally `expected.push("go","help","sync")` — so those three appear **twice** in `expected` today. Manual-run only (`CONTRIBUTING.md:29`), not wired into CI. | The deletion removes the latent duplicate; the assertion stays satisfied by the codex shims. No edit needed. |
| (not in brief) | ADR-215 §Consequences records the intended layout: *"Codex exposes 98 skills (95 canonical skills plus three command wrappers)"*, verified natively at the time — when `./skills` held **95** and `./codex/skills` held 3. `de2e50463` broke that arithmetic by adding the three wrappers to the shared directory as well. | The deletion **restores** ADR-215's verified numbers rather than invalidating them. Its `98` must **not** be rewritten to `95`. See `## Architecture Decision`. |

## Research Insights

### Premise Validation (Phase 0.6)

Both cited commits resolve and match their described content. `de2e50463` ("fix: expose
/soleur:go, /soleur:sync, /soleur:help as Devin slash commands (#8087)") created the three
shared shims and bumped `SKILL_DESCRIPTION_WORD_BUDGET` 2400 → 2442. `c99eeebe1`
("feat(devin): add Devin plugin scaffolding parity (#8088)") created
`plugins/soleur/devin/skills/{go,help,sync}/SKILL.md` and set
`.devin-plugin/plugin.json` `"skills": ["./skills", "./devin/skills"]`. No GitHub issue is
cited by the brief, and `gh issue list` surfaced no open issue tracking the duplicate-menu
symptom — file one first if a `Closes #N` reference is wanted.

**Capability claims verified rather than asserted** (`hr-verify-repo-capability-claim-before-assert`):
Grok's independence from the three shims was established from git history and the routing
table, not from the brief. Claude Code's manifest semantics were verified against live
documentation. The "no existing collision guard" claim was established by an exhaustive
sweep, not by absence of memory.

### Attribution receipts (independently re-verified)

Every historical claim the decision rests on was probed against `main` by a dedicated
history pass. All seven confirm.

```console
$ git log -1 --format="%H %ai %s" 3598693f4
3598693f4 2026-07-10 23:25:46 +0200 feat(grok): add project-level Grok Build config … (#6314)
$ git log -1 --format="%H %ai %s" 766199eda
766199eda 2026-07-11 00:04:20 +0200 feat: Grok fidelity Phase A+B — onboarding + harness adapter

# The load-bearing claim: when did the shared shim first appear?
$ git log --diff-filter=A --oneline -- plugins/soleur/skills/go/
de2e50463 fix: expose /soleur:go, /soleur:sync, /soleur:help as Devin slash commands (#8087)
# → first ADDED 2026-09-11, two months after the Grok adapter landed.
#   `plugins/soleur/commands/go.md` exists at BOTH endpoints (git show <sha>:<path>).

# Did that commit touch the grok branch of the harness adapter?
$ git diff de2e50463^..de2e50463 -- plugins/soleur/lib/harness.ts | grep -E "^[+-].*grok"
(no output)          # → zero grok-branch changes; all edits isolated to the devin branches.

# What did skills/ hold when ADR-215 was merged?
$ git ls-tree -r --name-only 8be1ba1a9:plugins/soleur/skills | grep -c 'SKILL.md$'
95                   # → exactly the "95 canonical skills" ADR-215 records.
```

The last receipt is the strongest single piece of evidence in this plan: at ADR-215's merge
commit `8be1ba1a9`, the shared directory held **95**, not 98. The three wrappers lived only
in the per-harness directory, exactly as this plan restores.

### Mechanism Minimality (Phase 0.6b)

**Property List** — what the change must buy:

- P1. Each of `/soleur:go`, `/soleur:help`, `/soleur:sync` appears exactly once in the
  Claude Code slash menu.
- P2. `/go`, `/help`, `/sync` keep working on Grok Build.
- P3. `/soleur:go`, `/soleur:help`, `/soleur:sync` keep working on Devin CLI.
- P4. `$soleur:go`, `$soleur:help`, `$soleur:sync` keep working on Codex.
- P5. Devin and Codex each resolve the three names once, not twice.
- P6. The collision class cannot silently recur.

**Cut List** — mechanisms named by the brief, removed before any research was spent on them:

| Mechanism | Property it would buy | What already buys it |
|---|---|---|
| New `plugins/soleur/grok/skills/{go,help,sync}/` | P2 | `plugins/soleur/commands/{go,help,sync}.md`, which Grok already loads as a Claude-compat plugin via `.grok/config.toml` `paths = ["./plugins/soleur"]` — and did for two months before the shims existed. **Cut.** |
| Repointing `harness.ts:174` and `:439` at a grok-specific path | P2 | Nothing — the `skills/${name}` interpolation is never evaluated with `go`/`help`/`sync`, and repointing it wholesale would break the other 95 skills that *do* route through it. **Cut.** |
| A `skills` allowlist/denylist in `.claude-plugin/plugin.json` | P1 | Does not exist; the key is additive-only. **Cut.** |
| Edits to the `.devin-plugin` / `.codex-plugin` `"skills"` arrays to de-duplicate | P5 | The deletion itself: once `skills/` no longer holds the three names, the union `./skills ∪ ./<harness>/skills` contains exactly one of each. **Cut.** |

Net effect: the brief proposed adding a directory, two code edits and a manifest edit. All
four are cut. What remains is a deletion plus a guard.

### Value proposition (Phase 0.6c)

Not a cost or performance saving — no measurement required. The change is net-negative
diff: three files deleted, one constant reverted, one count corrected, one guard added.

### Skill description budget (Phase 1.8)

Measured with the same tokenizer the gate uses (`components.test.ts:154`,
`desc.split(/\s+/).filter(Boolean).length`), over all 98 discovered skills:

- `SKILL_DESCRIPTION_WORD_BUDGET` = **2442** (`components.test.ts:16`).
- Measured cumulative total = **2442** — i.e. **2442/2442, exactly zero headroom.**
- `go` = 17, `sync` = 15, `help` = 10 words; sum **42**, matching `de2e50463`'s recorded
  `+42` bump verbatim.
- After deletion the measured total is **2400** — precisely the pre-`de2e50463` baseline.

The constant must be reverted to **2400** and the trailing `+42` clause dropped from its
bump-history comment. Leaving it at 2442 is *green* but silently grants 42 words of
unearned headroom that no future plan's headroom measurement
(`cq-skill-description-budget-headroom`) would attribute correctly. The three surviving
per-harness copies use different, shorter descriptions and are never counted —
`discoverSkills()` does not see them.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-02-25-plugin-command-double-namespace.md` — the
  plugin loader treats `commands/` and `skills/` names as one namespace. This is the
  mechanism.
- `knowledge-base/project/learnings/2026-02-12-command-vs-skill-selection-criteria.md` —
  "commands are invisible to agents; if an agent must invoke it, it must be a skill."
  Checked against this change: `go`/`help`/`sync` are human entry points and are never
  routing targets, so removing them as skills costs no agent capability.
- `knowledge-base/project/learnings/2026-02-22-skill-count-propagation-locations.md` —
  counts drift across `plugin.json`, both READMEs, `brand-guide.md` and the docs site.
  Grep for the *old value*; do not trust a memorized file list. Applied: the full sweep
  below found the manifests carry no counts at all and the docs site computes them.
- `knowledge-base/project/learnings/2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch.md` —
  a `set -euo pipefail` shell guard whose capture pipeline ends in `grep` **aborts with no
  output exactly when it finds the thing it was written to find**. This is why the guard
  below is a bun assertion, not a shell script.
- `knowledge-base/project/learnings/2026-08-09-my-tests-pinned-a-constant-by-indexing-it-and-my-mutants-read-as-survivors.md` —
  pin against an independent referent. The guard's referent is the loader's own
  registration rule, including the additive manifest key.
- `knowledge-base/project/learnings/2026-03-10-dogfood-collision-guard-requires-realistic-fakes.md` —
  a naively modelled guard passes vacuously. Hence the M4 manifest row and the M5
  own-dispatch floor.

### Count-propagation sweep (complete)

| Site | Current | After | Mechanism |
|---|---|---|---|
| `README.md:14` — `**68 agents**, **3 commands**, and **98 skills**` | 98 | 95 | Auto-maintained by `scripts/sync-readme-counts.sh`; **CI-gated** at `.github/workflows/ci.yml:265` (`--check`) |
| `plugins/soleur/README.md:78` — `\| Skills \| 98 \|` | 98 | 95 | Same script, same gate |
| `plugins/soleur/scripts/grok-pre-push-gate.sh:125` | — | — | Pre-push mirror of the same `--check` |
| `plugins/soleur/.claude-plugin/plugin.json` | no count, **no `skills` key** | unchanged | — |
| `.codex-plugin/plugin.json`, `.devin-plugin/plugin.json` | paths only, no counts | unchanged | — |
| Docs site (`docs/_data/stats.js`, `docs/_data/skills.js`) | computed, flat walk | auto | Every `{{ stats.skills }}` interpolation updates itself |
| `plugins/soleur/commands/help.md` | runtime-derived, no literal | unchanged | — |
| `grok-inspect-contract.test.ts:32` | static fixture `94` | passes | Fixture-parsed, not disk-derived |
| `lib/grok-inspect-contract.ts:21` | floor `MIN_SOLEUR_PLUGIN_SKILL_COUNT = 90` | passes | 95 ≥ 90. Note this floor lives in `lib/`, not in the test file |
| `components.test.ts:918-925` ("scan is wider than `skills/*/SKILL.md`") | 224 vs 98 | passes | Each deleted directory holds **only** `SKILL.md`, so both sides shrink by exactly 3 → 221 vs 95. The margin is **unchanged**, not widened; the strict `>` holds either way |
| `knowledge-base/engineering/codex-onboarding.md:86` — "Component counts remain 95 skills" | stale | **becomes accurate** | — |
| `plugins/soleur/devin/INSTRUCTIONS.md:78` — "~95 skills" | approximate | **becomes accurate** | — |
| `ADR-215:34,49` — "98 skills (95 canonical plus three command wrappers)" | true only by accident | **becomes true by construction** | Do **not** rewrite to 95 |
| `model.c4:117` — "61 workflow skills" | already stale by 37 | still stale | Pre-existing; scope out with a tracking issue |
| `docs/_data/skills.js:11` — `// Last verified: 2026-06-15 (4 categories, 91 skills)` | stale comment | still stale | Pre-existing; fold into the same tracking issue |
| `marketing-content-drift.test.ts:110` | discrete set `{59,61,62,63,65,66,67}` — not a range; `60` and `64` are absent | unaffected | 95 and 98 are outside the set. The new `// 62 plugin skills` comment cannot trip it either: the pattern needs the bigram `62 skills`, which that comment does not contain |

## Decision — REVISED after review. Read this section before any other.

> **An earlier revision of this plan chose (a′): delete the three shared shims. Multi-agent
> review falsified the premise that made (a′) safe, and the evidence was verified on disk.
> The decision is now (b′). The reasoning that follows is kept in full, because the parts
> that killed option (a) still hold — only the conclusion moved.**

### What review found that reverses the call

The plan asserted that removing the three skills "costs no agent capability," on the ground
that `GO_SKILL_ROUTES` never targets them. That reasoning is sound for the *plugin's own*
routing and wrong for the product. **`plugins/soleur/commands/*.md` are not model-invocable;
only skills are.** Three live production sites in `apps/web-platform` depend on
`Skill(soleur:go)` existing:

- `apps/web-platform/server/prompt-injection-wrap.ts:25` —
  `const POSTAMBLE = "Invoke /soleur:go on the user's intent.";` appended to **every**
  Command Center user message.
- `apps/web-platform/server/soleur-go-runner.ts:1333` — the Command Center baseline system
  prompt: *"Dispatch via the /soleur:go skill, which classifies intent and routes to the
  right workflow…"*
- `apps/web-platform/server/soleur-go-runner.ts:131` — *"Before invoking the Skill tool,
  emit a one-line text block naming the skill you're about to route to…"*

The Command Center persona passes `skills:` undefined at `cc-dispatcher.ts:2742`, so the SDK
loads every plugin skill and `Skill(soleur:go)` is in scope **today**. There is no
`SlashCommand` tool anywhere in this repo, and the postamble's `/soleur:go` sits mid-message
rather than at prompt-start, so slash expansion does not rescue it.

**The failure mode is measured, not hypothetical.** `prompt-injection-wrap.ts:26-29`
records it verbatim, from deployed-environment QA:

> *ADR-113 — the support persona … must NOT receive the `/soleur:go` dispatch instruction
> (the support system prompt has **no such skill in scope**, and the agent **visibly
> complains about the stray directive in every reply — user-facing noise found by
> deployed-env QA**).*

Deleting `skills/go/` puts the main Command Center persona into exactly that state.

A second, independent blocker: **`plugins/soleur/devin/skills/` has never been measured to
load.** Codex's equivalent is proven — ADR-215 §Verification records a real native probe,
and `scripts/codex-plugin-smoke.mjs` re-runs it. Devin has no such probe;
`devin-plugin.test.ts:28-35` only asserts the files exist on disk. The one measurement on
record cuts the other way: `devin/INSTRUCTIONS.md:78` records *"~95 skills"* measured
2026-09-15 against commit `cdee39de1`, which held **98** under `skills/` and **3** under
`devin/skills/` — a figure consistent with a single root loading. Meanwhile `de2e50463`'s
commit message is itself a positive measurement that Devin loads from `skills/` and *not*
from `commands/`. Deleting the shared copies risks re-introducing the exact bug that commit
fixed.

### Chosen: (b′) — hide the three shared shims from the menu with `user-invocable: false`

`user-invocable: false` is a documented Claude Code SKILL.md frontmatter key: it removes a
skill from the `/` menu while leaving it invocable by the model. That is precisely the
shape of this bug — the duplicate row is caused by a skill that is *both* named like a
command *and* user-invocable, and only the second half needs to change.

| | (a′) delete | **(b′) `user-invocable: false`** |
|---|---|---|
| Duplicate menu rows | fixed | **fixed** |
| `Skill(soleur:go)` for Command Center | **lost** | **preserved** |
| Devin entry point | unproven risk | **untouched** |
| Codex entry point | safe | **untouched** |
| Count / budget / marker-fleet churn | README 98→95, budget 2442→2400, fleet 67→65 | **none** |
| Diff size | 3 deletions + 6 edited files | **3 frontmatter lines** |

The per-harness copies under `codex/skills/` and `devin/skills/` do **not** get the key, so
even if a non-Claude harness honours it, those harnesses keep a registered, user-invocable
entry point. That is the belt-and-braces that makes (b′) safe where (a′) is not.

**What (b′) does not fix,** and must therefore be stated plainly rather than quietly
dropped: the Devin/Codex skills-vs-skills double-resolution (Property P5) survives, because
both manifest roots still carry all three names. Guard 1 clause (a) still detects it, so it
becomes a *known, guarded* condition rather than an invisible one. Closing it needs the
deletion, and the deletion needs a real Devin discovery probe first — filed as the
follow-up below.

### Sequencing

1. **This PR:** add `user-invocable: false` to the three shared shims; add Guard 1 (whose
   property becomes *no command stem collides with a **user-invocable** skill*); file the
   tracking issues.
2. **Follow-up, blocked on measurement:** build `scripts/devin-plugin-smoke.*` mirroring
   `codex-plugin-smoke.mjs`. Once `devin/skills/` is *proven* to register, delete the three
   shared shims, revert the budget to 2400, correct the marker fleet to 65 and the counts
   to 95, and repoint the three `apps/web-platform` dispatch sites. That is (a′), landed
   safely.

### Why option (a) is still rejected — unchanged, and still load-bearing

The premise that Grok needs these files is false (see `## Attribution receipts`), so a
`plugins/soleur/grok/skills/` directory buys nothing. Beyond that, every mechanism that
could register such a directory is either duplicate-creating or worse-sited than an
existing pattern: Claude Code's `skills` key is **additive**, so listing a per-harness path
in `.claude-plugin/plugin.json` surfaces it in Claude Code's own menu and re-creates this
bug; `.grok/config.toml` `paths` could take a second plugin root, and `.grok/agents/`
already shows the repo's real pattern for Grok compat artifacts is to **generate them under
`.grok/`**, not to add them to the plugin. (An earlier revision stated this as a two-branch
dichotomy; it is not exhaustive, and the argument stands on the falsified premise plus the
mechanism enumeration rather than on the dichotomy.)

### Superseded reasoning, retained for the record

The parent session's hypothesis (a) rested on the premise that Grok resolves `/go` from
`plugins/soleur/skills/go/SKILL.md`. That premise is false, and option (a) is not merely
unnecessary — **it is self-defeating**:

1. Claude Code's `skills` manifest key is **additive**: the default `skills/` scan always
   runs and listed directories load *alongside* it. Grok has no `.grok-plugin/` manifest;
   it loads `plugins/soleur` as a Claude-compat plugin via `.grok/config.toml`. So either
   (i) Grok reads `.claude-plugin/plugin.json`, in which case adding
   `"skills": ["./grok/skills"]` to make Grok see a new directory **also makes Claude Code
   see it**, re-registering `go`/`help`/`sync` and re-creating the exact duplicate this
   plan removes; or (ii) Grok does not read that manifest, in which case there is no way to
   register `grok/skills/` at all. Both branches defeat (a).
2. `harness.ts:174` interpolates `skills/${name}` for **all** skills. Repointing it at
   `grok/skills/` would break the other 95; a per-name exception would be needed for a code
   path that is never executed with those three names.

Option (b) as specified (a manifest allowlist/denylist) does not exist and is refuted.
Option (c) is rejected because a correct fix exists at negative diff cost.

**The deletion restores conformance with an already-recorded architectural decision.**
ADR-215 records 95 canonical skills in `skills/` plus three command wrappers in the
per-harness directory, and its §Verification confirms that was measured natively. Today
`skills/` holds 98 because the wrappers were also dropped into the shared directory. After
the deletion: `./skills` = 95 and `./codex/skills` = 3 → Codex exposes 98; `./skills` = 95
and `./devin/skills` = 3 → Devin exposes 98. ADR-215's numbers become true by construction.

## User-Brand Impact

**If this lands broken, the user experiences:** `/soleur:go` — the single entry point to
the entire product — missing or inert on Devin CLI or Codex, so the user's first typed
command after installing Soleur does nothing.

**If this leaks, the user's data / workflow / money is exposed via:** no exposure vector.
This change deletes three instruction files and adds a test. It touches no schema, no
secret, no credential, no network egress, no production surface and no user data.

**Brand-survival threshold:** `aggregate pattern` — a broken entry point would affect every
Devin/Codex user uniformly and is fully recoverable by revert; no single user suffers
irreversible harm.

## Files to Edit

Scope is (b′). **Nothing is deleted in this PR**, so every count, the description budget and
the cloud-mode marker fleet are all untouched.

- `plugins/soleur/skills/go/SKILL.md`, `.../help/SKILL.md`, `.../sync/SKILL.md` — add
  `user-invocable: false` to the frontmatter of each, plus a one-line comment naming why
  (the name collides with `commands/<name>.md`, and these copies exist to keep the skill
  model-invocable for the Command Center dispatch sites). **Three lines total.** Do **not**
  add the key to the `codex/skills/` or `devin/skills/` copies — those are the harness entry
  points and must stay user-invocable.
- `plugins/soleur/test/components.test.ts` — add Guard 1 in its own
  `describe("plugin slash-name uniqueness")` block (see `## Guard Contract`).
- `plugins/soleur/test/helpers.ts` — parameterize the discovery root
  (`discoverSkillsIn(root)`, with `discoverSkills() = discoverSkillsIn("skills")`) and
  expose each discovered skill's `user-invocable` frontmatter value, which Guard 1's
  property now turns on.
- `knowledge-base/engineering/architecture/decisions/ADR-224-*.md` — **new ADR** (see
  `## Architecture Decision (ADR/C4)`).

## Files to Delete

**None in this PR.** Deleting `plugins/soleur/skills/{go,help,sync}/` is option (a′), which
is deferred to the follow-up described in `## Decision` §Sequencing and blocked on a Devin
discovery probe. The count reverts that deletion requires — README 98→95,
`SKILL_DESCRIPTION_WORD_BUDGET` 2442→2400, marker fleet 67→65, and the
`scripts/codex-plugin-smoke.mjs` comment — all move to that follow-up with it. They are
documented in `## Research Insights` so the follow-up does not have to rediscover them.

## Files Explicitly NOT Changed (verified, not assumed)

- `plugins/soleur/lib/harness.ts` — both grok sites (`:174`, `:439`) remain correct for the
  95 skills that do route through `invokeSkill()`.
- `plugins/soleur/.claude-plugin/plugin.json` — has no `skills` key today and **must not
  gain one**; a per-harness path listed there would re-create this exact bug.
- `.codex-plugin/plugin.json`, `.devin-plugin/plugin.json` — the additive
  `["./skills", "./<harness>/skills"]` arrays stay; the deletion is what resolves the
  double-resolution.
- `plugins/soleur/test/{codex,devin}-plugin.test.ts` — assert against the per-harness
  directories only.
- `plugins/soleur/test/{harness,devin-harness,codex-harness}.test.ts` — assert on
  `routingInstructions()` / `INSTRUCTIONS.md` string content, not on file existence.
- `plugins/soleur/devin/skills/{go,help,sync}/SKILL.md` — **left alone deliberately.** An
  earlier draft proposed folding the deleted shims' `argument-hint:` frontmatter and the
  `help` shim's extra instructions into these wrappers. Verified on disk, there is nothing
  to fold: `argument-hint:` already exists verbatim at **line 4 of each
  `plugins/soleur/commands/{go,help,sync}.md`**, which is the canonical file these wrappers
  delegate to; the `help` shim's manifest-path and Glob-count steps restate
  `commands/help.md` Step 2; and the `go` shim's harness-adapter steps are already covered
  by `plugins/soleur/devin/INSTRUCTIONS.md:61` (skill → `/soleur:<skill>` slash command),
  `:62` (agents → `run_subagent`), `:70` (`$ARGUMENTS` handling) and `:249-250`. The Devin
  copies are four lines rather than twelve *because* they delegate. Folding prose in would
  also risk a third markdown link, which `codex-plugin.test.ts:32-39` and
  `devin-plugin.test.ts:28-35` reject (they assert exactly
  `[<harness>/INSTRUCTIONS.md, commands/<name>.md]`, in that order). Cutting this phase
  removes the only risky edit in the change; cite the line numbers above in the PR body as
  the supersession evidence.
- `plugins/soleur/test/grok-inspect-contract.test.ts`,
  `grok-agent-discoverability.test.ts`, `agent-registry.test.ts` — unaffected.
- `scripts/codex-plugin-smoke.mjs` — its latent duplicate resolves itself.
- The docs site, `commands/help.md`, `lefthook.yml`, `deploy-docs.yml` — all compute or
  path-filter; none carry a literal.

## Implementation Phases

### Phase 0 — Preconditions

1. **Install bun**, pinned to `.bun-version` (**1.3.14**). `command -v bun` is currently
   empty here (mise provides node, python, gh, claude, codex only), and
   `scripts/test-all.sh` gates its bun shard on it — so without bun the plugin suite,
   including the new guard, is silently skipped. Confirm `bun --version` matches.
2. Establish a green baseline **from the worktree root** (bun resolves `bunfig.toml` from
   the invocation cwd, and the root `bunfig.toml` excludes `.worktrees/**`, which does not
   apply to the worktree's own contents):
   `bun test plugins/soleur/test/components.test.ts plugins/soleur/test/devin-cloud-mode.test.ts plugins/soleur/test/codex-plugin.test.ts plugins/soleur/test/devin-plugin.test.ts`
3. Record the baseline counters that AC2 asserts are **unchanged**: 98 skills, budget 2442,
   marker fleet 67, `sync-readme-counts.sh --check` green.
4. Re-confirm the two premises the decision rests on:
   `grep -n 'Invoke /soleur:go' apps/web-platform/server/prompt-injection-wrap.ts` returns
   the postamble, and `plugins/soleur/devin/skills/{go,help,sync}/SKILL.md` all exist.

### Phase 1 — Write the guard FIRST and drive it RED (no fix yet)

1. Parameterize `discoverSkillsIn(root)` in `plugins/soleur/test/helpers.ts` and expose each
   discovered skill's `user-invocable` frontmatter value.
2. Extract `collidingNames({ commandNames, skillRoots })` and pin it with the
   synthesized-fixture controls from `## Guard Contract`.
3. Add the live-tree shell in its own `describe("plugin slash-name uniqueness")` block,
   implementing clauses (a), (b) and (c).
4. Add the cross-file guard-presence assertion (mutation row M8's mechanism).
5. **Run against the current, unmodified tree. It must FAIL** under clause (b), naming `go`,
   `help` and `sync` — they are user-invocable skills whose names collide with command
   stems. That is M1 observed for free. If it passes today, the guard is wrong — stop.

### Phase 2 — Apply the fix and go green

1. Add `user-invocable: false` to the frontmatter of
   `plugins/soleur/skills/{go,help,sync}/SKILL.md`, each with a one-line comment naming why.
2. Re-run the guard → GREEN.
3. Confirm AC2's four counters are still at their Phase 0 values — nothing was deleted, so
   nothing should have moved.

**Do not commit or push before Phase 2 completes.** Phase 1 leaves the tree deliberately
RED, and both `.github/workflows/ci.yml` and
`plugins/soleur/scripts/grok-pre-push-gate.sh:125` would block a push taken mid-phase.

### Phase 3 — Walk the mutation matrix

Execute every row M1–M8, reverting each before the next, recording per row the `git diff`
hunk with its line range, the reddening test's name, and a failure-message excerpt. Apply
each mutation as a **line-scoped** hunk, never a file-wide `s///` — `components.test.ts` is
~968 lines of near-identical `expect(...).toEqual([])` blocks.

### Phase 4 — Per-harness journey checks

Run AC6 (Grok), AC7 (`node scripts/codex-plugin-smoke.mjs`) and AC8 (Devin), recording in
the PR body that AC8 is an on-disk check rather than a discovery probe.

### Phase 5 — ADR-224

Re-derive the next free ordinal against freshly-fetched `origin/main`, then write ADR-224
per `## Architecture Decision (ADR/C4)` and append the one-line pointer to ADR-215
§Consequences.

### Phase 6 — Full battery and follow-ups

`bash scripts/test-all.sh`, satisfying AC10's executed-test-count requirement. File the two
follow-up issues from AC11.

## Guard Contract

### Guard 1 — plugin slash-name uniqueness guard

**Property.** No name is *presented* twice to a user for any harness this plugin ships to.
"Presented" rather than "registered" is load-bearing: a skill that is registered but not
user-invocable is reachable by the model and absent from the menu, which is exactly the
state (b′) creates. Two distinct collision classes, and an earlier draft covered only the
first:

- **P-a (Claude Code, commands-vs-skills).** The filename stems under
  `plugins/soleur/commands/*.md` are disjoint from the skill names Claude Code registers.
  This is the defect this PR fixes.
- **P-b (Codex and Devin, skills-vs-skills).** `plugins/soleur/.codex-plugin/plugin.json`
  and `plugins/soleur/.devin-plugin/plugin.json` each declare
  `"skills": ["./skills", "./<harness>/skills"]` — **two roots, today**. A name present in
  both roots resolves twice. This is precisely the second defect the deletion fixes
  incidentally, and it is Property P5 in the list above. Nothing would guard it if the
  contract stopped at P-a: adding `devin/skills/review/` tomorrow would collide with
  `skills/review/`, Devin would resolve it twice, and a commands-vs-skills guard would be
  green because `review` is not a command.

**Assembly.** **Glob-discover** every `plugins/soleur/.*-plugin/plugin.json` — do not
enumerate the three that exist today, or a future `.grok-plugin/plugin.json` is a blind
spot by construction. For each discovered manifest `M`, let `R(M)` = the default `skills/`
scan ∪ each path in `M.skills` (the key is **additive**, never a replacement). Assert:

- **(a)** within each `R(M)`, no skill name appears in more than one root → buys P-b/P5;
- **(b)** every **user-invocable** skill name in `R(M)` is disjoint from the
  `commands/*.md` stems → buys P-a/P1. The `user-invocable` qualifier carries the whole
  fix under (b′): a skill with `user-invocable: false` does not render in the `/` menu, so
  it cannot produce a duplicate row. A guard that ignored the flag would red on the shipped
  tree and would be asserting a property this plan deliberately does not hold;
- **(c)** `plugins/soleur/.claude-plugin/plugin.json` declares **no `skills` key at all**.

Clause (c) is deliberately stronger than (b) alone: it fails even on a *non-colliding*
addition. Claude Code is the one harness whose default `skills/` scan shares a namespace
with `commands/`, and there is no denylist, so the only safe number of additive roots there
is zero. It also converts what would otherwise be a one-shot acceptance checkbox into a
standing CI assertion.

Clauses (a) and (c) together answer the "is the manifest arm speculative?" challenge: it is
not. Clause (a) is exercised on every CI run by the two manifests that carry two roots
each, so the arm is live rather than dormant.

**Skill-name derivation mirrors the loader** — a skill is a *directory containing
`SKILL.md`*. `plugins/soleur/test/helpers.ts` `discoverSkills()` already implements exactly
this rule, which is why `plugins/soleur/skills/flag-bootstrap/` (it holds only `SETUP.md`)
is correctly not a skill. The rule is therefore free, not new. What is missing is a
**parameterized root**: `discoverSkills()` hardcodes `skills/`, so the guard cannot reuse it
for a manifest-listed directory without inlining a second copy of the glob that can drift
from the first. Parameterize it — `discoverSkillsIn(root)`, with
`discoverSkills() = discoverSkillsIn("skills")` — and `helpers.ts` moves into
`## Files to Edit`.

**Extract the decision as a pure function** —
`collidingNames({ commandNames, skillRoots }): string[]` — and pin it with **synthesized
fixtures**, mirroring the permanent-control block this same file already carries (whose own
comment reads *"the live corpus is clean, so the corpus assertion below compares `[]` to
`[]` and proves nothing"*). The live-tree assertion is then a thin outer shell over a
function whose behaviour is proven by controls that run every CI run, not by one-shot
mutations that are reverted. Satisfies `cq-test-fixtures-synthesized-only`.

**Home:** its own `describe("plugin slash-name uniqueness")` in
`plugins/soleur/test/components.test.ts` — **not** inside the existing
`describe("Kebab-case filenames")` block. Kebab-case is about naming *form*; this guard is
about namespace *uniqueness*, and filing it there would label every failure with a heading
that contradicts it and make the acceptance-criterion `-t` filter ambiguous.

**Mutation matrix.** Derived from the design above, not from a finished implementation.
Every row names a **fully valid fixture** and the assertions it **co-fires**, so a RED is
attributable to this guard rather than to a neighbour.

| # | Mutation | Expected |
|---|---|---|
| M1 | Remove `user-invocable: false` from `plugins/soleur/skills/go/SKILL.md` — the exact state this PR fixes, and the state of the tree today | RED naming `go`. Observed for free in Phase 1, before the fix is applied. No co-firing: the budget and counts are unchanged under (b′) |
| M2 | **Must-PASS, genuinely non-canonical:** create `plugins/soleur/commands/flag-bootstrap.md` with valid frontmatter | **GREEN.** `skills/flag-bootstrap/` holds no `SKILL.md`, so it is not a skill and this is not a collision. Pins the one derivation rule the Assembly argues for, and proves the guard does not over-reject |
| M3 | Create `plugins/soleur/commands/qa.md` (valid frontmatter, non-empty body), colliding from the **commands** side against the existing `skills/qa/` | RED naming `qa`. Proves the guard is not hardcoded to the three names this PR removes |
| M4 | **Second member:** with M3 in place, also create `plugins/soleur/commands/review.md` | RED naming **both** `qa` and `review`. Proves it reports the whole set rather than stopping at the first |
| M5 | **Clause (c), one `jq` edit, no filesystem change:** add `"skills": ["./devin/skills"]` to `plugins/soleur/.claude-plugin/plugin.json` | RED. Check `plugins/soleur/test/plugin-version-fallback.test.ts` for co-firing — it also reads a plugin manifest |
| M6 | **Clause (a) — the skills-vs-skills class, the row that makes the manifest arm live:** create `plugins/soleur/devin/skills/review/SKILL.md`, duplicating the existing `skills/review/` | RED naming `review` for the Devin manifest. A commands-vs-skills-only guard is green here — that is the whole point of the row |
| M7 | **Own dispatch (anti-vacuity), driven through the pure function rather than by mutating shared helpers:** feed `collidingNames()` empty `commandNames` / empty `skillRoots` | RED against the bounded floor `{ commands: >= 3, skills: >= 90, roots: >= 1 }` — never a silent pass. Bounded, not pinned: exact counts drift on every legitimate component addition and `sync-readme-counts.sh --check` already gates those |
| M8 | **Harness row with a real mechanism:** delete the guard's `describe` block entirely | RED in a **different file** — a cross-file presence assertion that reads `components.test.ts` and asserts the guard's identifying token, in the style of the orphan-doc guard this file already carries. A suite cannot detect its own neutering from inside itself, which is why the earlier "replace the assertion body with a tautology" row was incoherent and has been replaced |

Every mutation must be applied as a **line-scoped diff hunk**, never a file-wide `s///`:
`components.test.ts` is ~968 lines of near-identical `expect(...).toEqual([])` blocks, and a
global substitution rewrites a neighbouring assertion instead.

**Anchor.** The guard stores no value — it derives every side from the working tree and the
glob-discovered manifests at run time, so no constant exists that a single diff could edit
to weaken it while it still reports success. The synthesized-fixture controls (and M8's
cross-file presence assertion) cover the remaining weakening path, which is editing or
deleting the guard itself. By contrast `devin-cloud-mode.test.ts`'s `marked.length === 65`
**is** a stored constant — noted because this plan changes it, and because a future diff
that both adds a marker and bumps that constant proves consistency, not integrity.

**Implementation note — why bun and not shell.** Implemented as a `bun:test` assertion in
`components.test.ts`, which `scripts/test-all.sh` runs in the `bun` shard that rolls into
the required `test` check. Deliberately not a `*.test.sh`: per
`2026-09-07-the-guard-i-wrote-died-on-the-case-it-was-written-to-catch`, a shell guard
under `set -euo pipefail` whose capture pipeline ends in `grep` aborts with **no output at
all** precisely when a collision is found — the one case a collision guard most needs to
explain. If a reviewer insists on shell, every `grep` must carry `|| true`, the pattern
`plugins/soleur/test/c4-count-parity.test.sh` already documents.

## Architecture Decision (ADR/C4)

### ADR — mint ADR-224 (harness-neutral), cross-reference from ADR-215

An earlier revision proposed amending ADR-215. Review surfaced two reasons that is wrong,
both verified:

1. **ADR-215 would contradict itself.** The addendum's headline claim is *"Claude Code's
   `skills` manifest key is additive."* ADR-215 §Verification records the **opposite**
   semantics for the same-named key in Codex: *"It caught a real failure: a single custom
   skill root hid the canonical skills."* That is replace-default behaviour. Putting both
   statements in one document is a trap — a future reader will lift one sentence and apply
   it to the wrong harness. Whatever is written **must be harness-qualified in every
   clause**.
2. **Discoverability.** The rule's audience is the next harness author, who will not look
   inside a document titled *"Codex plugin reuses canonical Soleur components."* ADR-223
   (per-harness hook registries with a disposition ledger) is the harness-neutral sibling
   this belongs beside.

Mint **ADR-224** — provisional; a sweep of all 83 `refs/remotes/origin/*` refs shows
ADR-223 as the highest claimed, but the ordinal must be re-derived against freshly-fetched
`origin/main` immediately before merge, because a sibling branch can claim it mid-session.

Content, every clause harness-qualified:

1. **The placement rule.** Harness-specific entry-point wrappers live in
   `plugins/soleur/<harness>/skills/`. A wrapper placed in the shared
   `plugins/soleur/skills/` directory is visible to Claude Code, whose menu shares one
   namespace with `plugins/soleur/commands/` — so it renders twice. Where a shared-directory
   skill is genuinely needed for model invocability, it carries `user-invocable: false`.
2. **The manifest-semantics divergence, stated per harness.** Claude Code's `skills` key is
   **additive** — the default `skills/` scan always runs and listed directories load
   alongside it, and there is no allowlist or denylist. Codex's measured behaviour is
   **replace-default** (`knowledge-base/engineering/codex-onboarding.md:83`, and ADR-215
   §Verification). Do not generalise either.
3. **Why Grok has no per-harness directory.** Per-harness compat artifacts have two homes:
   *inside* the plugin for harnesses that read a manifest `skills` array (Codex, Devin), and
   *outside* it for Grok, whose compat surface is generated under `.grok/` — `.grok/agents/`
   holds 67 generated stubs produced by `plugins/soleur/scripts/sync-grok-agent-compat.ts`.
   Grok resolves `/go`, `/help`, `/sync` from `commands/`. The asymmetry is the model, not
   an oversight.
4. **Upstream does not forbid this.** Claude Code treats commands and skills as separate
   component types; the duplicate row is the documented consequence of registering both, not
   a loader violation. The uniqueness rule is therefore a **Soleur convention**, enforced by
   Guard 1 — say so, or the next reader hunts for an upstream rule that does not exist.

Then append a one-line pointer to ADR-215 §Consequences so its 95 + 3 arithmetic cites its
governing rule. **ADR-215's existing `98` figures at lines 34 and 49 stay unchanged** — they
describe Codex's total exposure and are not affected by (b′) at all.

### C4 views — no C4 impact

Per the completeness mandate, all three model files were read, not keyword-grepped:
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`.

Enumeration checked and found already modeled, with nothing added or removed:

- **External human actors:** none added or removed; `founder` unchanged.
- **External systems:** none added or removed. `codex`, `devin` and the Grok harness
  (`model.c4:212`, "Local Grok Build harness … Loads plugins/soleur via .grok/config.toml")
  are all already modeled, and their relationships to `platform.plugin` are unchanged —
  each still "loads canonical skills, command wrappers, agent instructions".
- **Containers / data stores:** none. The `skills` container (`model.c4:115`) still exists
  and still holds workflow skills; only its member count changes.
- **Access relationships:** none. No actor↔surface access boundary moves.

**Cardinality check:** `plugins/soleur/test/c4-count-parity.test.sh` derives heartbeat
workflows, monitor counts, GitHub monitor slugs and Resend emitters. It derives **no skill
or command count** (verified: `grep -niE 'skill|agent|command'` over that file returns two
comment lines, neither a derivation). This change therefore cannot red it, but Phase 5 runs
it rather than reasoning about it.

**Pre-existing defects found and scoped out.** Per `wg-when-an-audit-identifies-pre-existing`,
file one tracking issue (`type/chore`, `domain/engineering`) covering both:

- `model.c4:117` reads `"61 workflow skills — brainstorm, plan, work, review, compound, etc."`
  The live figure is 98 today and 95 after this change. "61" is already stale by 37 and is
  **not** falsified by this plan. Do not silently rewrite a cardinality whose intended
  denominator ("workflow skills" vs. all `SKILL.md` files) has not been established; the
  issue should also decide whether `c4-count-parity.test.sh` deserves a skills row.
- `plugins/soleur/docs/_data/skills.js:11` — `// Last verified: 2026-06-15 (4 categories, 91 skills)`.

## Open Code-Review Overlap

**None.** All 65 open `code-review`-labelled issues were fetched and each planned path
(`plugins/soleur/skills/{go,help,sync}`, `plugins/soleur/test/components.test.ts`,
`plugins/soleur/lib/harness.ts`, `plugins/soleur/devin/skills`, `plugins/soleur/README.md`)
was matched against every issue body via `jq --arg`. Zero matches.

## Observability

Plan Phase 2.9's trigger set (`apps/*/server|src|infra`, `plugins/*/scripts/`) does not
match — but deepen-plan Phase 4.7's skip condition is narrower (pure-docs only), and this
plan edits `.ts` test files. Read fail-closed, the gate applies, so the full schema is
declared rather than waived. The observable surface of a test-only change is the CI gate
itself, and declaring it is not box-ticking: it is what makes the guard's recurrence
detection auditable.

```yaml
liveness_signal:
  what: the required `test` check — Guard 1 in components.test.ts, the corrected
        marker-fleet assertion in devin-cloud-mode.test.ts, and the README count gate
  cadence: every push to every pull request
  alert_target: the pull request's own required-check status; a red `test` blocks merge
  configured_in: scripts/test-all.sh (bun + scripts shard registration);
                 .github/workflows/ci.yml:265 (sync-readme-counts --check);
                 plugins/soleur/scripts/grok-pre-push-gate.sh:125 (pre-push mirror)

error_reporting:
  destination: GitHub Actions job logs for the test-bun and test-scripts shards,
               surfaced on the pull-request check
  fail_loud: yes — Guard 1 throws naming every colliding name, and its anti-vacuity
             floor throws when zero commands are enumerated, so a mis-scoped guard
             fails rather than passing silently

failure_modes:
  - mode: a future harness shim is added to plugins/soleur/skills/, re-creating the collision
    detection: Guard 1 (components.test.ts)
    alert_route: red `test` check on the pull request that introduces it
  - mode: a per-harness skills path is added to .claude-plugin/plugin.json, re-registering
          the three names with Claude Code without any filesystem change
    detection: Guard 1's manifest arm (mutation row M4)
    alert_route: red `test` check on the pull request that introduces it
  - mode: a skill is added or removed and the README counts drift
    detection: scripts/sync-readme-counts.sh --check
    alert_route: red `test` check via .github/workflows/ci.yml:265, plus the pre-push mirror
  - mode: a cloud-mode marker is added or removed without updating the fleet count
    detection: devin-cloud-mode.test.ts marker-fleet assertion
    alert_route: red `test` check on the pull request

logs:
  where: GitHub Actions run logs for the test-bun and test-scripts shards
  retention: the repository's GitHub Actions default retention

discoverability_test:
  command: bash -c 'cd plugins/soleur && comm -12 <(ls commands/*.md | xargs -n1 basename | sed "s/\.md$//" | sort) <(for d in skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done | sort)'
  expected_output: (empty — no name appears both under commands/ and as a skill)
```

The probe was executed both ways before this plan was written: against the current tree it
prints `go`, `help`, `sync`; against a tree with those three excluded it prints nothing. It
needs no credentials, no network and no remote shell, and its first token is an allowlisted
probe verb.

**Gate-trigger false positives, recorded so the next reader does not re-investigate.**
Phase 4.5's keyword scan matches `504` and `firewall` in this plan, and Phase 4.9's glob
scan matches one line. All three are self-references, not triggers: `504` is a substring of
the commit SHA `de2e50463`; `firewall` appears only in the `## Infrastructure (IaC)`
sentence enumerating the resource classes this change does *not* introduce; and the
UI-surface glob matches only the `## Domain Review` sentence asserting that no path matches
it. This is the same class as the `iac-plan-write-guard` denial recorded in
`## Sharp Edges` — asserting an absence by naming the token you are absent of.

## Encryption Posture

**Skipped — detection does not fire.** No persistent data store and no new cross-component
or network connection is introduced. No file matches `\.tf$`,
`supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$` or `docker-compose.*\.ya?ml$`.

## GDPR / Compliance

**Skipped.** No regulated-data surface is touched: no schema, migration, auth flow, API
route or `.sql` file. None of the four expansion triggers fire — no LLM or external-API
processing of operator data is added, the brand-survival threshold is not `single-user
incident`, no scheduled workflow reads `learnings/` or `specs/`, and no new artifact
distribution surface is created (the plugin's distributed surface *shrinks* by three files).

## Infrastructure (IaC)

**Skipped — detection does not fire.** The change introduces no server, service, scheduled
job, vendor account, DNS record, certificate, secret, firewall rule or monitoring webhook,
and prescribes no provisioning step of any kind. It deletes three instruction files,
adjusts two test constants, adds one test, refreshes two script-owned README counts and
appends one ADR addendum.

## Acceptance Criteria

### Pre-merge (PR)

1. **The fix.** Each of `plugins/soleur/skills/{go,help,sync}/SKILL.md` carries
   `user-invocable: false` in its frontmatter, and **none** of the six per-harness copies
   under `plugins/soleur/{codex,devin}/skills/` does:

   ```bash
   for n in go help sync; do
     grep -q '^user-invocable: false$' "plugins/soleur/skills/$n/SKILL.md" || exit 1
     for h in codex devin; do
       grep -q '^user-invocable:' "plugins/soleur/$h/skills/$n/SKILL.md" && exit 1
     done
   done; exit 0
   ```

2. **Nothing was deleted, so nothing drifted.** All three counters are **unchanged** from
   the pre-PR baseline: `find plugins/soleur/skills -type f -name SKILL.md | wc -l` → `98`;
   `SKILL_DESCRIPTION_WORD_BUDGET` is still `2442`;
   `devin-cloud-mode.test.ts` still asserts `toBe(67)`;
   `bash scripts/sync-readme-counts.sh --check` still reports `98 skills` and prints
   "All component counts are in sync". An accidental deletion reds all four.
3. **The guard runs under its own name.**
   `bun test plugins/soleur/test/components.test.ts -t "plugin slash-name uniqueness"`
   reports a **non-zero pass count**. Exit 0 alone is insufficient — `bun test -t` exits 0
   when the filter matches zero tests, so a renamed guard would satisfy a naive check.
4. **Every mutation-matrix row M1–M8 was executed and observed.** Per row the PR body
   records the mutation's `git diff` hunk **with its line range**, the name of the test that
   reddened (or passed, for the must-PASS rows), and an excerpt of its failure message. A
   verdict word is what a dormant mutation and a real one both produce. M1 was observed RED
   on the pre-fix tree.
5. **Claude Code — the reported symptom.** Covered mechanically by AC1 + AC3; the rendered
   menu itself is AC12.
6. **Grok journey.** `plugins/soleur/commands/{go,help,sync}.md` each exist and carry a
   frontmatter `name:` matching their stem (Grok exposes plugin commands by frontmatter
   name), and `bun test plugins/soleur/test/grok-inspect-contract.test.ts` passes.
7. **Codex journey.** `node scripts/codex-plugin-smoke.mjs` passes. This is the **only
   mechanical proof in the repo that a per-harness `skills` root actually registers**, and
   it must be run rather than reasoned about.
8. **Devin journey.** `bun test plugins/soleur/test/devin-plugin.test.ts` passes. **State
   explicitly in the PR body that this is an on-disk existence check, not a discovery
   probe** — no Devin equivalent of `codex-plugin-smoke.mjs` exists. Under (b′) that gap is
   not load-bearing, because the shared copies Devin is measured to load are retained; it is
   the blocker for the (a′) follow-up.
9. **Command Center capability preserved.** `plugins/soleur/skills/go/SKILL.md` still
   exists, so `Skill(soleur:go)` remains in scope for the dispatch sites at
   `apps/web-platform/server/prompt-injection-wrap.ts:25` and
   `soleur-go-runner.ts:131,1333`. `user-invocable: false` suppresses menu rendering only,
   never model invocation. No file under `apps/web-platform/` is modified by this PR.
10. **The battery actually executed.** `bash scripts/test-all.sh` is green **and**
    `bun --version` equals `.bun-version` (1.3.14) **and** the bun shard reports a non-zero
    executed-test count, captured in the PR body. `scripts/test-all.sh` gates its bun shard
    on `command -v bun`, so "the battery is green" is *also true of a run that executed none
    of the plugin tests*. The AC4 mutation outcomes must come from a run satisfying this.
11. **Follow-ups filed.** (i) The (a′) deletion, blocked on building
    `scripts/devin-plugin-smoke.*` modelled on `codex-plugin-smoke.mjs`, carrying the
    already-measured count reverts (README 98→95, budget 2442→2400, marker fleet 67→65, the
    smoke-script comment) so they need not be rediscovered. (ii) One `type/chore` issue for
    the stale literals: `model.c4:117` ("61 workflow skills"),
    `docs/_data/skills.js:11` ("4 categories, 91 skills"), and
    `knowledge-base/engineering/grok-onboarding.md:62` ("67 Soleur agents" against 68).
12. **Diff subset.** The diff touches only: the three
    `plugins/soleur/skills/{go,help,sync}/SKILL.md` frontmatters,
    `plugins/soleur/test/components.test.ts`, `plugins/soleur/test/helpers.ts`, the one test
    file carrying the cross-file guard-presence assertion, the new ADR-224 file, plus the
    pipeline-written artifacts (this plan, `tasks.md`, `knowledge-base/INDEX.md`, and any
    `session-state.md` the run commits). **No `apps/`, no `README.md`, no deletions.**

### Post-merge (operator)

13. Operator confirms in a fresh Claude Code session that typing `/soleur` lists
    `/soleur:go`, `/soleur:help` and `/soleur:sync` exactly once each, and that
    `/soleur:qa` still appears once.
    *Automation: not feasible because this asserts the Claude Code TUI's own rendered slash
    menu, which is the harness the agent runs inside; no API, CLI flag or file artifact
    reports the composed menu, and a pre-fix reading is unobtainable from inside a session
    that already loaded the plugin. The mechanical half — the frontmatter state that drives
    the rendering — is AC1, and the collision property is Guard 1, both in CI.*

## Test Scenarios

**Guard behaviour is specified once, in `## Guard Contract`'s mutation matrix (M1–M8).** An
earlier draft restated those eight rows here as T2–T7 and then counted them as separate
coverage; they are the same observations in different words, so they are not repeated. The
scenarios below are the ones the matrix does *not* cover — regressions in neighbouring
suites and the end-user-visible outcome.

| # | Scenario | Expectation |
|---|---|---|
| T1 | `/soleur` in Claude Code after the change | `go`, `help`, `sync` appear once each; `qa` still appears once (the control that identified the mechanism, unchanged) |
| T2 | `bun test plugins/soleur/test/devin-cloud-mode.test.ts` | GREEN at `marked.length === 65`; the FR4-union test also green |
| T3 | `bun test plugins/soleur/test/{codex,devin}-plugin.test.ts` | GREEN — wrapper link targets untouched, and both manifests' `skills` arrays still resolve |
| T4 | `bash scripts/sync-readme-counts.sh --check` | "All component counts are in sync", 95 skills |
| T5 | `bun test plugins/soleur/test/grok-inspect-contract.test.ts` | GREEN — on-disk 95 ≥ `MIN_SOLEUR_PLUGIN_SKILL_COUNT` (90, at `lib/grok-inspect-contract.ts:21`) |
| T6 | `bun test plugins/soleur/test/components.test.ts` (whole file) | GREEN — budget at 2400/2400, and the `918-925` wider-scan test still holds at 221 vs 95 |
| T7 | `node scripts/codex-plugin-smoke.mjs` | Unchanged behaviour — the `expected` set still contains `go`/`help`/`sync`, now sourced solely from the explicit push rather than duplicated with the walk |

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Devin's `/soleur:go` breaks because the shared shim was load-bearing after all | Low | `.devin-plugin/plugin.json` declares `./devin/skills`, and `devin-plugin.test.ts` already asserts those wrappers resolve to `commands/<name>.md`. The Devin copies are strictly richer — they carry the cloud-mode block and an explicit "resolve these paths relative to this SKILL.md" instruction the shared copies lack. |
| **Devin silently switches which file it executes.** `.devin-plugin/plugin.json` declares two roots, so `go`/`help`/`sync` resolve **twice today** and the manifest does not specify which copy wins. If Devin takes the first match, Devin users are currently running `skills/go/SKILL.md` and will run a *different file* after the deletion. | Medium | This is a behaviour change, not a no-op, and the plan should not claim otherwise. It is safe because the delta was enumerated rather than assumed: `argument-hint:` is canonical at `commands/{go,help,sync}.md:4`; the `help` shim's extra steps restate `commands/help.md` Step 2; and the `go` shim's adapter steps are covered by `devin/INSTRUCTIONS.md:61,62,70,249-250`. Cite those line numbers in the PR body — they are the proof that this is supersession rather than substitution. |
| A Devin-specific instruction is lost with the deleted files | Low | Verified on disk that nothing is lost — see the row above and `## Files Explicitly NOT Changed`. The earlier plan to fold content forward was cut because the content already exists in two other files. |
| Grok's `/go` breaks | Very low | Grok ran without these files for two months (2026-07-10 → 2026-09-11). `invokeSkill()` is never called with `go`/`help`/`sync`. `harness.ts` is unchanged. |
| A count assertion elsewhere goes stale | Low | Swept exhaustively (see Research Insights). The manifests carry no counts; the docs site computes them; `sync-readme-counts.sh --check` is the CI gate for both READMEs; `devin-cloud-mode.test.ts` is handled explicitly; `grok-inspect-contract` floor is 90. Two genuinely pre-existing stale literals are scoped out with a tracking issue. |
| The guard passes vacuously | Medium | M5 (own-dispatch floor) and M6 (harness row) exist precisely for this, and M7 proves it does not reject everything. |
| The guard cannot be driven RED because bun is missing | **High — present today** | Phase 0 step 1 installs bun pinned to `.bun-version` (1.3.14) before any other work. |
| **The guard is green in CI because it never ran.** `scripts/test-all.sh` gates its bun shard on `command -v bun`, so a run without bun reports success having executed none of the plugin tests. A guard whose entire value is standing recurrence detection, living inside a shard that can silently skip itself, is this plan's own cited learning — *the guard I wrote died on the case it was written to catch* — reproduced one level up. | **High** | AC8 closes it: the battery being green is not sufficient; `bun --version` must equal `.bun-version` and the bun shard must report a non-zero executed-test count, captured in the PR body, and the AC5 mutation outcomes must come from such a run. The stronger alternative — making the missing-bun branch in `test-all.sh` **fail** rather than skip — is a one-line change worth raising with the reviewer, but it widens scope beyond this PR and is left as a recommendation. |

## Sharp Edges

- **`bun` is not installed in this environment.** `command -v bun` is empty; mise provides
  node, python, gh, claude and codex only. `scripts/test-all.sh` gates its bun shard on
  `command -v bun`, so a run without bun reports success having executed none of the plugin
  tests — including the new guard. Install 1.3.14 first.
- **Invoke `bun test` from the worktree root, not the bare repo root.** Root `bunfig.toml`
  sets `pathIgnorePatterns = [".worktrees/**", ...]`; bun resolves `bunfig.toml` from the
  invocation cwd, and `plugins/soleur/bunfig.toml` documents that a preload registered only
  at the repo root does not apply to `cd plugins/soleur && bun test`.
- **`devin-cloud-mode.test.ts`'s `67` is invisible to a literal grep** for `skills/go` — the
  suite enumerates with `readdirSync` over two roots. It is the concrete instance of the
  brief's warning about constructed references, and the only test in the repo that actually
  breaks on the deletion.
- **`skills/help/SKILL.md` carries no cloud-mode marker** while `go` and `sync` do. The
  fleet count drops by 2, not 3 — `67 → 65`, not `64`.
- **The count is 98 → 95, not 99 → 96.** `skills/flag-bootstrap/` has no `SKILL.md`, so
  directory count and skill count differ by one. A plan written against 99 → 96 red-lines
  the CI drift gate.
- **Never add a `skills` key to `.claude-plugin/plugin.json`.** It is additive, not a
  filter; any per-harness directory listed there is surfaced in Claude Code's menu and
  re-creates this bug. AC10 pins this.
- **Do not hand-edit README counts.** `sync-readme-counts.sh` owns the exact literals; a
  hand edit differing in whitespace or emphasis fails `--check` at `ci.yml:265`.
- **A guard written in shell dies on the case it was written to catch.** Under
  `set -euo pipefail`, a capture whose pipeline ends in `grep` aborts with no message when
  the grep matches nothing. Use the bun assertion, or guard every `grep` with `|| true`.
- **Writing this plan tripped its own gate.** An earlier revision asserted the absence of
  manual-provisioning steps by *naming* one of the guard's trigger tokens; the
  `iac-plan-write-guard` hook correctly denied the write. State absence without reproducing
  the forbidden literal.

## Alternatives Considered

| Option | Verdict | Reason |
|---|---|---|
| **(a)** Add `plugins/soleur/grok/skills/{go,help,sync}/`, repoint both `harness.ts` grok sites, then delete from `skills/` | **Rejected** | Rests on a false premise (Grok never used these files). Self-defeating: the Claude Code `skills` key is additive, so registering a grok directory re-creates the duplicate; and if Grok does not read `.claude-plugin/plugin.json`, the directory cannot be registered at all. Also forces a per-name exception into a `harness.ts` code path never executed with these three names. |
| **(a′)** Delete the three shared shims; no new directory; no `harness.ts` change | **Deferred to a follow-up, not rejected** | Correct in the long run and still the end state, but it removes `Skill(soleur:go)` — live on every Command Center message via `prompt-injection-wrap.ts:25` — and reproduces the ADR-113 measured failure; and it deletes the only *proven*-loading Devin root while the replacement has never been measured. Land it once a Devin discovery probe exists. |
| **(b)** Suppress via a `skills` allowlist/denylist in `.claude-plugin/plugin.json` | **Refuted** | The key exists but is additive-only; the default `skills/` scan always runs. No denylist or allowlist exists in the manifest schema. |
| **(b′)** Keep the files, add `user-invocable: false` to each shared `SKILL.md` | **CHOSEN** | The documented frontmatter key removes a skill from the `/` menu while leaving it model-invocable — exactly the half of the property that is wrong. Fixes the reported symptom in a three-line diff, preserves `Skill(soleur:go)` for the Command Center, leaves every harness entry point untouched, and needs no count, budget or marker-fleet churn. The per-harness copies deliberately do **not** carry the key, so a harness that honours it still has a registered entry point. Its remaining gap — the Devin/Codex double-resolution — is detected by Guard 1 clause (a) rather than hidden. |
| **(b″)** `skillOverrides` in `settings.json` | **Rejected** | Per-user local configuration. Not shippable in a plugin, so it cannot fix the bug for anyone who installs Soleur. |
| **(d)** Mirror image — delete the three **commands**, keep the skills | **Rejected, with reasons** | Raised at review as the direction `2026-02-12-command-vs-skill-selection-criteria.md` nominally prescribes ("if an agent must invoke it, it must be a skill"). It would dissolve the collision from the other side and make `harness.ts:174`'s `skills/${name}` literally true for Grok. Rejected because `commands/*.md` are the **canonical implementations**, not wrappers: 214 + 155 + 945 = 1,314 lines versus the 22-line shim. Both per-harness wrapper sets delegate *into* them, and `eval-harness/gated-skills.json:3` gates on `plugins/soleur/commands/go.md`. Option (d) is therefore a migration of the entry-point corpus, not a hygiene fix — a separate architectural decision that would also empty `commands/` and take the README's "3 commands" to 0. |
| **(c)** Accept the duplicate rows and document why | **Rejected** | There is no parity cost to pay. A three-line frontmatter change fixes the operator-visible symptom with no capability loss and no count churn. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — plugin tooling/hygiene change. The mechanical
UI-surface override did not fire: no path in `## Files to Edit` or `## Files to Delete`
matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx` or any other
UI-surface glob. The plan touches instruction markdown, two test files, two READMEs and one
ADR. Product/UX Gate: NONE.


---

## Addendum — 2026-09-17 (work phase)

Appended rather than edited: the body above is the record of what was planned, and a
correction that overwrites it destroys the evidence of what was believed at plan time.

**Falsified: "no Devin discovery probe exists."** The plan gates the (a′) follow-up on
building `scripts/devin-plugin-smoke.*`, on the premise that `plugins/soleur/devin/skills/`
had never been measured to load. `devin skills list` is a first-class subcommand and reports:

```
/soleur:go [user,model] (…/0.0.0-unversioned/skills/go)
/soleur:go [user,model] (…/0.0.0-unversioned/devin/skills/go)
```

Both roots register; `help` and `sync` likewise. There is no probe to build, and the
follow-up issue drops that task. The reading was taken against a pre-PR plugin cache, so it
establishes that `devin/skills/` loads — it does **not** establish whether Devin honours
`user-invocable: false`, which stays unmeasured and is scoped as such in ADR-224.

**Superseded: the stated reason to defer deletion.** The real blocker is dispatch, not
discovery. `plugins/soleur/skills/go/` is the sole model-invocable `Skill(soleur:go)` handle
— `commands/go.md` is user-typed only, `apps/web-platform/server/` wires no `SlashCommand`
tool, and `soleur-go-runner.ts:2162` keys sticky-workflow detection on `toolName === "Skill"`.

**Corrected during implementation.** Three clauses of `## Guard Contract` as specified could
not hold on the shipped tree:

- Clause (a) would have been RED after the fix — Codex and Devin each resolve `go`/`help`/`sync`
  from two roots today (now measured on both harnesses). Resolved with a by-name ack, so a new
  cross-root duplicate still reds; mutation row M6 proves it.
- Clause (b) as specified quantified over every root in `R(M)`, which could only be satisfied by
  breaking the Codex and Devin entry points. Scoped to the default `skills/` root.
- "**Glob-discover** every `plugins/soleur/.*-plugin/plugin.json`" does not work: Bun's `Glob`
  does not match dot-directories, and the pattern returns `[]` — a guard reporting a clean sweep
  having examined nothing. Replaced with a dirent scan plus a discovery floor.

**Task 7.3 rescoped.** The plan names three stale-literal sites; there are four (`nfr-register.md:32`
carries the same "61 workflow skills"). Per the filing-site net-flow gate they are inlined, not filed.

### Addendum 2 — 2026-09-17 (review round)

**§Test Scenarios T2/T4/T5/T6 and §Sharp Edges carry option (a′) figures and are
SUPERSEDED.** They read `marked.length === 65`, `95 skills`, `budget 2400/2400`
and `fleet 67 → 65`. Those are the DELETION option's numbers. This plan chose
(b′), states so at §Decision, at "All three counters are unchanged", and in
`tasks.md`, and nothing is deleted — so the live tree is 98 skills, budget 2442,
marker fleet 67, and `devin-cloud-mode.test.ts` asserts `toBe(67)`. Anyone
executing that table against the shipped branch gets four false expectations.
Superseded here rather than edited, because the table is the record of what (a′)
would have required.

**The clause (b) description in Addendum 1 is also superseded.** It says
"Scoped to the default `skills/` root". After review the guard DERIVES its roots
from `.claude-plugin/plugin.json`; that equals `["skills"]` only because clause
(c) forbids the key. ADR-224 decision 4 carries the current rule.

**A premise this plan rests on was falsified by measurement.** The plan defers
deletion because `plugins/soleur/skills/go/` is "the sole model-invocable
`Skill(soleur:go)` handle". Probed with all three shims deleted,
`Skill(soleur:help)` still succeeds and returns `commands/help.md` — commands are
model-invocable and shadow same-named skills on Claude Code. Deletion is still
deferred, but for a different and narrower reason: Codex, Devin and Grok each
resolve `skills/{go,help,sync}` and would be affected. ADR-224 §Consequences
carries the corrected version.
