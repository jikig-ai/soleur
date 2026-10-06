---
title: "feat: Cursor CLI harness support"
date: 2026-10-06
slug: feat-cursor-cli-harness-support
branch: feat-cursor-harness-support
issue: 9608
type: feat
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Soleur already runs its lifecycle inside Codex, Devin, and Grok Build. The Cursor CLI has no adapter, so a session there is `unknown` and is pointed at tools that CLI does not have. This plan adds a plugin installed from this repository: bare `/go` and `/sync`, a generated `soleur-` name for every other skill and agent, and a harness arm that recognizes the session only after the CLI marker is measured.

The work is two slices on issue #9608. Slice 1 ships the plugin, the names, and the arm, and states that hooks do not run. Slice 2 ports the full guard set after the hook envelope is measured. The plugin is called supported only when slice 2's committed shape note quotes `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and the guards firing. This plan does not set `closes` in frontmatter. Slice 1's PR must not close #9608. Slice 2's PR body is the one that contains `Closes #9608`.

Public docs, comparison pages, the marketplace listing, the editor agent, and Cloud Agents stay outside both slices.

## Research Insights

In this plan, **harness** means a host agent runtime named by the `Harness` union in `plugins/soleur/lib/harness.ts`. The word is not in `knowledge-base/project/glossary.md`. It does not mean a test harness.

### Premise Validation

Checked on 2026-10-06 against the worktree `feat-cursor-harness-support` at `93723f35a2` and against issue state. Held: #9608 is open and is the parent; #6320 and #8299 stay closed; draft PR #9598 is open on this branch; the `Harness` union is `"claude" | "grok" | "codex" | "devin" | "unknown"`; there is no `.cursor-plugin`, no `cursor/INSTRUCTIONS.md`, and no Cursor hook registry. Stale premise, corrected here: the skills-key rule is no longer an open analogy. Cursor's plugin reference, fetched 2026-10-06, says a specified component field replaces folder discovery and the default folder is not also scanned. What remains unmeasured is a live Cursor CLI session, not the documented replace rule.

### Property List

1. On the Cursor CLI, `/go` classifies and runs the canonical phases.
2. `/sync` stays bare. Every other skill and agent is `soleur-` prefixed and resolves once, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`.
3. A session is `cursor` only after a marker measured on the Cursor CLI. Instructions for that session do not name the Skill tool, the Task tool, `run_subagent`, or AwaitShell.
4. Slice 1 states that hooks do not run. Slice 2 shows each guard firing on the Cursor CLI protocol before the plugin is called supported.
5. A setup step adds the plugin from the local path. A second machine can add it from the git repository. Nothing is submitted to cursor.com.
6. README, getting-started, comparison, FAQ, blog, and battlecard stay unchanged until slice 2 is green.
7. The canonical skill and agent tree stays the source. Cursor names are generated.

### Cut List

- Marketplace listing. Buys no property in the list. It is a different publisher contract. Not filed.
- Hand-copied skill tree. The canonical-source property is already bought by a generator plus a `Harness` member (ADR-245).
- Public README or FAQ sentence in this plan. Deferred as #9610, blocked by #9608.
- Cloud Agents. The skills page says unsynced local skills are not copied there. Out of both slices.
- Cursor IDE editor agent. Deferred as #9611, blocked by #9608.
- Reopening #6320 or #8299. Both are closed. They do not cover this adapter.
- A Codex-shaped `skills` array of `./skills` plus a second root. The documented Cursor rule is replace, not that array. A second root is also how `/go` can be registered twice and still pass `harness-discovery`.
- A guessed session marker. `CURSOR_AGENT` is documented on the terminal-tools page as non-empty when Cursor is running. The page does not say it is CLI-only. It is not a `detectHarness` predicate until a Cursor CLI session and a non-CLI session are both measured.
- A second authored copy of skill `description:` lines. A generator may project bytes under a generated header. It does not author a parallel description.
- An Anysphere processor or DPA row. No new store and no Cursor token.
- A comparison page or battlecard edit. Marketing non-goal.
- A `harness-discovery` CI job for Cursor. The parameters page fetched 2026-10-06 has `agent mcp list` and no skills-list command. TR6 stays closed until a pinned CLI can list skills headlessly.

Codex, Devin, and Grok adapters do not cover these properties. Each one has its own manifest, name spelling, and hook registry.

### Repo surfaces

Worktree `93723f35a2`. No Cursor adapter directory. `plugins/soleur/hooks/hooks.json` exists (2109 bytes). `plugins/soleur/skills`, `commands`, and `agents` exist. There is no `rules/` directory and no `mcp.json` at the plugin root (`plugins/soleur/.mcp.json` is a different filename). Default Cursor discovery of an omitted field would therefore load `skills/`, `commands/`, `agents/`, and `hooks/hooks.json`.

Symbols that share the fallthrough a new member hits:

- `detectHarness`, `formatSkillInvocation`, `spawnAgent`, `pollInstructions`, and `routingInstructions` in `plugins/soleur/lib/harness.ts`. The first three call `detectHarness()` and take no harness argument. `routingInstructions` default names the Skill tool, the Task tool, and `grok inspect`. `pollInstructions` has real arms for the four current members. Its default does not name AwaitShell.
- `formatSkillRef` in `plugins/soleur/lib/workflow-fidelity.ts`. Codex, Grok, and Devin have arms. The default emits `soleur:<skill>` with no slash. No arm emits `/soleur-<name>`.
- `invokeSkill` and `formatAgentSpawn` in the same harness module, reached from `dispatchGoRoute` in `plugins/soleur/lib/go-routing.ts`. Unknown gets Skill and Task.
- `behindSyncInstructions` in `plugins/soleur/lib/pr-merge-poll.ts`. Only `grok` and `claude` are special-cased. The default runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"`. Slice 1 adds a `cursor` arm that refuses that script. Leaving `cursor` on the default is the fallthrough.
- `TIER_MAPS` in `plugins/soleur/lib/harness-model-map.ts`. Codex and Devin already inherit because they are absent. Do not add a Cursor model id.
- `POPULATION_GLOBS` in `plugins/soleur/lib/harness-parity.ts`. `codex/skills` and `devin/skills` are inside the census. `.grok/agents/` is outside it. R5 and R9 mark `soleur-engineering-cto` and `/soleur-plan` as non-canonical inside that population. Generated Cursor files follow the Grok placement: outside the census. `plugins/soleur/test/harness-parity-tree.test.ts` pins `EXEMPT` at 21, all in `commands/go.md`, and it pins three `harness-forms` regions in that file. New Cursor spellings go inside those three regions. A fourth region fails even after the count moves.
- `plugins/soleur/test/components.test.ts` expects manifest dirs `.claude-plugin`, `.codex-plugin`, `.devin-plugin`. A fourth `.*-plugin` directory fails that equality. `rootsFor` always prepends `skills`, so a replacing `skills` field that hides `./skills` still looks additive. `ACKED_CROSS_ROOT_DUPES` allows `go`, `help`, and `sync` twice. Neither is loader proof.
- `plugins/soleur/scripts/sync-grok-agent-compat.ts` is the generator shape (`--check` on missing, drifted, or extra stubs). It also rewrites `.claude-plugin/agents.manifest.json` and embeds `GROK_STUB_SPAWN_RULE`. A Cursor generator does not edit that script or `grok-fidelity-gate.sh`.
- `scripts/setup-codex.sh` and `scripts/setup-devin.sh` are local-path setup steps. Neither is a Cursor argv. Devin's git install string lives in `plugins/soleur/devin/INSTRUCTIONS.md`.
- `plugins/soleur/scripts/emit-decision.sh` repeats the four markers and otherwise records `harness=unknown`. Same change as `detectHarness`, and only after the marker is measured.
- `plugins/soleur/commands/go.md` and `commands/help.md` are what a session reads. Help's Grok collision was solved as `local:help`. That is not the Cursor name.

Tests that stay green while a Cursor loader is wrong: `harness-tool-map.test.ts` (Codex and Devin tables only), `harness-parity.test.ts`, `harness-parity-tree.test.ts`, the additive skills model in `components.test.ts`, `harness-discovery-smoke.ts` (`codex` | `devin` only, and `k` roots may list a name `k` times), and `harness.test.ts` (empty env expects `unknown`).

### Spec versus codebase

| Spec claim | Reality at `93723f35a2` | Plan response |
|---|---|---|
| No Cursor manifest, instructions, command entry, agent projection, or hook registry. | Confirmed by directory and content search. | Slice 1 creates the manifest, instructions, and generator. It does not create a hook registry. |
| An unmatched session is told to use the Skill tool and the Task tool. | `routingInstructions` default does that. | Slice 1 adds an explicit `cursor` arm for the functions that take a `Harness`. `detectHarness` stays unchanged until the marker is measured, so a live session remains `unknown` until slice 2. |
| Model tier inherits. | `resolveModelTier` returns `inherit` for any member absent from `TIER_MAPS`. | Do not add a Cursor row. |
| Invocation is `/go`, `/sync`, and `/soleur-<name>`. | No renderer emits the hyphen form. | New arms in `routingInstructions` and `formatSkillRef`. |
| Generated hyphen forms can live beside Codex and Devin wrappers. | R5 and R9 reject those spellings inside `POPULATION_GLOBS`. | Generated tree stays outside the census, same placement as `.grok/agents/`. |
| Slice 1 ships the arm, and the env marker is not written until measured. | `formatSkillInvocation`, `invokeSkill`, `spawnAgent`, and `formatAgentSpawn` cannot see a `Harness` argument. | Slice 1 arms `routingInstructions`, `pollInstructions`, `workflowFidelityInstructions`, `formatSkillRef`, and `behindSyncInstructions`. Slice 2 wires detection, then the four no-argument functions, in the same change. |
| Green tool-map, parity, or `components.test.ts` is not loader proof. | Confirmed. | A new test fails when the canonical root is hidden or `/go` is registered twice, and it does not call `rootsFor` or reuse `ACKED_CROSS_ROOT_DUPES`. |
| Public pages stay unchanged. | `plugins/soleur/README.md` still says the other three harnesses. That sentence is true today. | Neither slice edits it. |
| Terms parenthetical waits for the `cursor` arm. Six other legal pages also list the four CLIs. | Confirmed. None name Cursor. | Terms stay out of both slices. The other six are not authorized. |

### Institutional learnings that change this plan

1. `2026-09-11-codex-native-plugin-discovery.md`. Install is not loadability. Slice 1 does not copy a skills array. A discovery job is added only if a pinned CLI can list skills.
2. `2026-02-25-plugin-command-double-namespace.md` and `2026-02-12-plugin-loader-agent-vs-skill-recursion.md`. The generator writes flat names, not `commands/soleur/`. Acceptance fails if `/go` or `/sync` is prefixed or any other name carries the plugin id twice.
3. `2026-07-17` Grok spawn filename-stem and `2026-07-11` Grok YAML quoting. The agent check is a spawn attempt or an explicit refusal. Do not encode colon-to-hyphen or description quoting as Cursor rules. Do not reopen #6320.
4. `2026-04-09` OpenHands porting and the archived `2026-09-18` cross-harness parity brainstorm. Generator plus `--check`, compare body bytes. `harness-parity.test.ts` names Cursor in the same change as the arm only for files inside the census. Population stays derived. #8299 stays closed.
5. `2026-09-18` census-cell, `2026-09-20` every-instrument, `2026-09-27` remedy-must-name-a-source, `2026-09-10` six-instruments. No `:-` fallback, no unbraced plugin root, no guessed `plugins/soleur` path. A fence includes an unset root, a decoy root, and a control that fails when the decider always passes.
6. `2026-09-15` Devin dual hook, `2026-09-11` Grok hook aliases, `2026-05-10` empirical hook shape, `2026-10-05` hook event with no command field, `2026-09-17` Devin envelope omits cwd, `2026-04-12` hook paths, `2026-04-09` OpenHands hook protocol. A hook is three claims: the registry loads, the matcher matches, the body runs. Slice 1 ships no loadable registry. "Hooks do not run" needs a witness that lists loaded commands and a positive control. Slice 2 starts with a fresh-session capture and a date-stamped shape note, then a disposition ledger in the `devin-dispositions.tsv` shape. Fail closed when the captured envelope has no working directory.
7. `2026-07-11` Grok `/go` inlines the pipeline. Classification plus a draft PR is not the lifecycle. Support waits until slice 2 shows `/go` dispatching into the skill, one pipeline skill finishing its gates, and no same-turn product edits presented as completion.
8. `documentation-gaps/devin-cloud-plugin-surface-matrix`. `plugins/soleur/cursor/INSTRUCTIONS.md` is a per-surface matrix. Slice 1 marks hooks absent and leaves every unmeasured surface unmeasured. The file does not say supported.
9. `2026-09-11` meta-harness-is-not-a-union-member and `2026-06-08` portability scan. Add one Cursor CLI member only after the marker and the carrier are measured, with a negative test that a Claude-shaped or Grok-shaped process without that marker stays on its current arm.
10. `2026-09-22` AI-harness credentials are runtime inputs and `2026-03-20` bare-repo plugin hook sync. No Doppler, token, or credential contract. A live login is not a slice 1 gate.

### External documentation

Fetched 2026-10-06. Local ADR-245, ADR-223, and ADR-224 stay the authority for how Soleur adds a harness. These pages settle the Cursor loader contract that those ADRs do not name.

- <https://cursor.com/docs/reference/plugins> and <https://cursor.com/docs/plugins>. Cursor Plugins use `.cursor-plugin/plugin.json`. A specified component field replaces folder discovery. Default folders are `skills/`, `rules/`, `agents/`, `commands/`, `hooks/hooks.json`, and `mcp.json`.
- <https://cursor.com/docs/skills>. Skill `name` is lowercase letters, numbers, and hyphens, and must match the folder. Invocation is `/skill-name`. Colons are outside that set. `disable-model-invocation: true` means user-typed only. Project and user skill dirs include `.cursor/skills/`, `.agents/skills/`, and, for compatibility, `.claude/skills/` and `.codex/skills/`.
- <https://cursor.com/docs/cli/reference/slash-commands>. Built-ins include `/plan`, `/help`, and `/shell`. `/go` and `/sync` are not on that table. `/review` is a built-in skill on the skills page, not a row on the slash-command table. The collision stands either way.
- <https://cursor.com/docs/hooks> and <https://cursor.com/docs/reference/third-party-hooks>. Event names are camelCase (`sessionStart`, `beforeShellExecution`). The common input object is snake_case and includes `workspace_roots`. Exit code 2 blocks. This is the hypothesis slice 2 captures. It is not a binding copied into the tree in slice 1.
- Plugin reference, MCP section. `${CURSOR_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_ROOT}` expand in `command`, `args`, `env`, and `cwd` there. `${PLUGIN_ROOT}` does not expand. Expansion inside `hooks.json` is unmeasured.
- <https://cursor.com/docs/agent/tools/terminal>. `CURSOR_AGENT` non-empty means Cursor is running. CLI versus IDE is unmeasured.
- <https://cursor.com/docs/cli/reference/parameters>. `--plugin-dir <path>` loads a local plugin directory. No skills-list subcommand. `agent plugin marketplace add <git-url>` is in the changelog, not in that parameter table.
- <https://cursor.com/docs/plugins> publish section. Public listing is a human submission at cursor.com/marketplace/publish. Out of scope.
- <https://cursor.com/docs/subagents>. Foreground blocks. Background returns immediately. No named wait or poll tool.
- <https://cursor.com/terms-of-service>. Last updated September 3, 2026. Wording stays "a Soleur plugin that runs in Cursor" and "not affiliated with or endorsed by Anysphere."

### Functional overlap

Registries queried on 2026-10-06: api.claude-plugins.dev, claudepluginhub.com, and the Anthropic marketplace catalog. Nothing installed. skillshare, import-command, agnix, and buildkite were skipped. None is a `Harness` member plus a generator for this repository.

### Related issues and PRs

- #9608 parent, open. #9611 IDE, #9610 public sentence, #9609 productize checklist. All three are blocked by #9608 and stay deferred.
- #9598 draft PR on `feat-cursor-harness-support`.
- #6320 and #8299 stay closed.
- Adjacent open issues that mention Cursor and are not this adapter: #9329, #5821, #2057, #1588, #9110, #3026, #8201. Do not reuse them.

### Conventions that bind the slices

Constitution: core workflow stages are skills; `go`, `sync`, and `help` are the entry commands; a new harness decision is an ADR written with the change, not after it; component counts are computed, not hardcoded; plugin behavior changes by editing files, not by runtime registration. ADR-179 forbids a `:-` plugin-root fallback. ADR-223 gives each harness its own registry and a disposition ledger. ADR-226 deleted `SUPPORTED_HARNESSES`. C4 already draws Codex, Devin, and Grok Build as external systems that load `platform.plugin`. A Cursor CLI box is the same kind of addition. `views.c4` includes `devin` and `platform.grokBuild` and does not include `codex`. The new box follows the Devin and Grok include, so both edge endpoints are in the view.

No `description:` edit to `plugins/soleur/skills/*/SKILL.md` is a candidate. The skill-description budget check does not run.

## Research Reconciliation — Spec vs. Codebase

The table in Research Insights is the reconciliation. Three facts change the design relative to a straight copy of Codex or Devin:

- `formatSkillRef` has no hyphen arm, and `POPULATION_GLOBS` rejects `/soleur-<name>` inside the census. Generated Cursor files stay outside that census.
- Cursor's documented `skills` field replaces folder discovery. Slice 1 sets a single path, `./cursor/skills`. It does not copy the Codex array `["./skills", "./codex/skills"]`.
- Omitting `hooks` would discover `plugins/soleur/hooks/hooks.json`. The plugin reference types `hooks` as a path to a config file or an inline config, not a directory. Slice 1 sets it to `./cursor/hooks-empty.json`, whose `hooks` object is `{}`. That file is not a copy of the Claude or Devin registry.

## Problem Statement

An operator who already runs Soleur in Codex, Devin, or Grok Build cannot run the same lifecycle in the Cursor CLI. `Harness` has no `cursor` member. A session there is `unknown`, and `routingInstructions` for `unknown` names the Skill tool and the Task tool.

Cursor's `/` menu is one list. `/plan`, `/help`, and `/shell` are CLI built-ins. `/review` is a built-in skill. `/go` and `/sync` are not on the slash-command table fetched 2026-10-06. Skill names are lowercase letters, numbers, and hyphens. A colon is outside that set.

The plugin root already contains `skills/`, `commands/`, `agents/`, and `hooks/hooks.json`. Default discovery of an omitted field would load those folders. That loads colliding bare names and presents the Claude hook file as a Cursor registry.

## Proposed Solution

Slice 1 ships a Cursor plugin manifest, a generated name map, and explicit instruction arms. Hooks are stated as not running, and the manifest does not point at `hooks/hooks.json`. `detectHarness` does not grow a predicate in this slice, so a live session stays `unknown` until slice 2.

Slice 2 measures the CLI marker and the hook envelope, then wires detection and the guard registry. The plugin is called supported only when that slice shows `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and each guard firing.

Public docs stay unchanged in both slices. The Terms parenthetical is a later Tier 2 patch, after `harness.ts` contains `cursor`, and it is not part of either slice.

## Technical Approach

Detail level is A LOT: two slices, a new harness member, and an architecture decision.

### Architecture

The manifest is `plugins/soleur/.cursor-plugin/plugin.json` (Cursor Plugins format, fetched 2026-10-06 from <https://cursor.com/docs/reference/plugins>). Component fields that are set replace the default folder. Fields that are omitted keep the default. This manifest sets:

- `skills` to `./cursor/skills` (one string, not an array).
- `agents` to `./cursor/agents`.
- `commands` to `./cursor/commands`, a directory with no `*.md` file, so `plugins/soleur/commands/` is not scanned.
- `hooks` to `./cursor/hooks-empty.json`. The plugin reference (fetched again 2026-10-06) types that field as a path to a hooks config file, or an inline config. A directory does not replace discovery. The file is `{ "hooks": {} }`. It registers no events. It is not `hooks/hooks.json` and it is not a copy of the Claude or Devin registry.

`rules` and `mcp` stay omitted. There is no `rules/` directory and no `mcp.json` at the plugin root. The manifest key is `mcpServers` when set. This plan does not set it.

The generator `plugins/soleur/scripts/sync-cursor-name-map.ts` reads the canonical tree and writes:

- `cursor/skills/go/SKILL.md`, `cursor/skills/sync/SKILL.md`, and `cursor/skills/soleur-help/SKILL.md`. Their bodies point at `commands/go.md`, `commands/sync.md`, and `commands/help.md`, relative to the plugin root. They do not point at `skills/go/SKILL.md`, `skills/sync/SKILL.md`, or `skills/help/SKILL.md`. Those three files are the Devin shims: they name the Skill tool, the Task tool, `run_subagent`, and `CLAUDE_PLUGIN_ROOT`. Paths do not start with `plugins/soleur/`. `--plugin-dir` is already that directory, and a second machine installs the plugin root, not this monorepo.
- `cursor/skills/soleur-<folder>/SKILL.md` for every other canonical skill. The folder name matches `name`. The body points at `skills/<folder>/SKILL.md`, relative to the plugin root.
- `cursor/agents/soleur-<stem>.md` for every canonical agent. Stem is the path under `agents/` with `/` replaced by `-`, so `agents/engineering/cto.md` becomes `soleur-engineering-cto`. `--check` fails when two sources map to one output name. The body points at `agents/<path>.md`, relative to the plugin root. It does not embed `GROK_STUB_SPAWN_RULE` or name `spawn_subagent`.

Every generated stub starts with one header: on Cursor, do not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell, and do not expand `CLAUDE_PLUGIN_ROOT`. If the canonical file tells you to, stop. The header is not a second description. `/go` and `/sync` are skills in that map, not commands, so the `/` menu has one registration of each. Help is only `soleur-help`. The help stub fails `--check` if its body contains `Detect the active harness as Devin`. Stub frontmatter carries `name` and, when the canonical file has a `description`, that same description text as a quoted YAML scalar under the generated header. A colon inside the text, as in `soleur:finance:cfo`, stays inside the scalar. The generator copies those bytes. It does not author a second sentence. The generated `plan`, `help`, and `review` stubs also set `disable-model-invocation: true`, so a request to plan, help, or review does not enter Cursor's built-in mode. A canonical file with no `description` does not gain an invented one. `--check` compares those bytes and prints `cursor-name-map ok` when the tree matches. There is no second shell checker.

One spelling function. `go` and `sync` render as `/go` and `/sync`. Every other skill renders as `/soleur-<name>`, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`. Agents render as `/soleur-<stem>` with the stem above. `formatSkillRef`, the generator's `name` field, and the cursor arms of `routingInstructions` use that function. A uniform `/soleur-<skill>` arm is a failed slice: it emits `/soleur-go`.

`routingInstructions("cursor")` composes `workflowFidelityInstructions("cursor")` and `pollInstructions("cursor")`. `workflowFidelityInstructions` gets a cursor arm in slice 1. It says to read the canonical file the stub names. It does not cite the Claude Stop hook, and it does not name the Skill tool or the Task tool. `pollInstructions("cursor")` and `behindSyncInstructions("cursor")` are one short stop. The stop says no wait primitive has been measured, this run cannot finish that gate, and the next action is to continue that merge on a harness that already has a wait, or to stop. It does not invent a wait and it does not ask the operator to watch. That stop does not make the plugin supported. The cursor arm of `behindSyncInstructions` does not contain `CLAUDE_PLUGIN_ROOT`. The default arm of that function does, and a `cursor` member with no case would hit it. `TIER_MAPS` gains no Cursor row.

Local setup is `scripts/setup-cursor.sh`. It resolves `plugins/soleur` from its own path with `BASH_SOURCE` and passes `--plugin-dir` with that absolute path. It does not call `readlink -f`, `timeout`, `sed -i`, or `date -d`. That flag is on <https://cursor.com/docs/cli/reference/parameters>, fetched 2026-10-06. The script exits non-zero when `agent` is not on `PATH`. It prints that `agent` is not on `PATH` and stops. It does not prompt for a token, it does not open an install URL, and it does not ask for a login. It prints the absolute `agent --plugin-dir` line for the next session, and it prints that this slice does not classify the session as `cursor`, does not run hooks, and does not block a commit. It does not run `agent plugin marketplace add`. A symlink under `~/.cursor/plugins/local` loads only when the target resolves to a directory inside that folder. Cursor skips a symlink that points at a plugin repository elsewhere on disk (<https://cursor.com/docs/plugins>, Test plugins locally, fetched 2026-10-06), so the script does not use that symlink shape.

The git-repository install is a separate step: `agent plugin marketplace add <git-url>` from the CLI changelog of 2026-07-13, cited at <https://cursor.com/docs/cli/changelog>. The URL is this repository. It is not a submission to cursor.com/marketplace/publish. The plugin reference says a repository whose plugin is not at the repo root lists it in `.cursor-plugin/marketplace.json` at that root. This repo's file names marketplace `soleur`, owner `jikig-ai`, and one plugin whose `source` is `plugins/soleur`. Resolution looks for `plugins/soleur/.cursor-plugin/plugin.json`. If that command fails, the exit is to clone the repository and run `scripts/setup-cursor.sh`. Slice 2 reads `--help` on the installed CLI before that git step is called verified on that machine. <!-- verified: 2026-10-06 source: <https://cursor.com/docs/cli/reference/parameters> --> <!-- verified: 2026-10-06 source: <https://cursor.com/docs/reference/plugins> -->

### Implementation Phases

#### Phase 1: Name map and instruction arms

The first task is `/architecture create 'Add a Cursor CLI plugin adapter'` (provisional ADR-273). The title does not say supported. No product code lands before that ADR file exists. The decision body says the support bar is the end of slice 2.

Then the manifest, the empty hooks file, the repo-root marketplace file, the generator, `--check`, the instructions file, and the `Harness` arms that already take a harness argument, including `behindSyncInstructions`. `detectHarness` is unchanged. `plugins/soleur/cursor/INSTRUCTIONS.md` is the per-surface matrix: this plugin file registers no hook events, slice 1 does not classify the session as `cursor`, and every unmeasured surface stays marked unmeasured. Whether the CLI also loads `.claude/settings.json` is one of those surfaces. The file does not say other hook sources are off, and it does not say the plugin is supported. `commands/go.md` puts the Cursor spellings inside the three existing `harness-forms` regions. Those regions say Cursor's `/plan`, `/help`, `/review`, and `/shell` are built-ins, the Soleur names are `/go`, `/sync`, `/soleur-plan`, `/soleur-help`, and `/soleur-review`, and a Cursor session does not call the Skill tool, the Task tool, `run_subagent`, or AwaitShell. The same region says slice 1 does not run hooks and does not classify the session as `cursor`. `commands/help.md` gains a Cursor column with those same names, and it names the four built-ins as names not to type. A git install does not run the setup script, so that limit is in `commands/go.md`, the stub header, and `INSTRUCTIONS.md`, not only on setup stdout.

Success criteria: the tests in Guard Contract 1, 2, and 3 are red before the implementation and green after it. A Claude-shaped or Grok-shaped env still resolves to its current arm. The setup script's stdout contains the absolute `--plugin-dir` line and the slice-1 limit sentence.

#### Phase 2: Measured marker and guard port

Starts with a fresh Cursor CLI session capture and a date-stamped shape note. The note's first rows are which hook sources the CLI loaded, then the marker, the hook envelope, the working directory field, and the tool names that actually fired. Documented `CURSOR_AGENT` is a candidate only. It becomes the predicate only if the capture shows it on the CLI and a non-CLI Cursor process does not set it. A predicate that also matches the IDE is a failed slice. A session that lacks the marker stays `unknown`. This plan does not add a second Cursor signal, and it does not change the unknown stop for the other harnesses.

Then `detectHarness`, `invokeSkill`, `spawnAgent`, `formatSkillInvocation`, `formatAgentSpawn`, and `emit-decision.sh` share that marker. The cursor check is placed after the Claude, Grok, Codex, and Devin arms, immediately before `unknown`. `CLAUDECODE` plus the marker still returns `claude`. In that same change, the four no-argument functions, with the marker set and `CLAUDECODE` unset, emit `/go`, `/sync`, and `/soleur-<name>`, and they do not return the Skill tool or the Task tool. The only hook file is slice 1's `plugins/soleur/cursor/hooks-empty.json`, filled from the capture. If the capture shows the CLI does not load that path, slice 2 adds no second registry, fails closed, and does not call the plugin supported. This plan does not add a repo-level `.cursor/hooks.json`. It does not add a command the capture already shows firing from another source. `.claude/settings.json` is a named row in that source list, marked already-fires or dead before any guard command is copied from it. Any other ledger row of that kind is already-fires or dead. `.claude/hooks/cursor-dispositions.tsv` and `.claude/hooks/cursor-matcher-parity.test.sh` follow the Devin ledger shape. Paths inside the plugin config stay fail-closed until the capture shows the variable that expands to the plugin root. Hook commands are not selected by the `detectHarness` marker. The envelope's `user_email` is not stored.

`pollInstructions` and `behindSyncInstructions` name a wait tool only when the capture contains one. Until then they keep the slice 1 refusal. The `## Tools` table and `harness-tool-map.ts` gain a Cursor column only when the capture lists tool names. A `harness-discovery` job is added only when a pinned CLI can list skills headlessly. The parameters page fetched 2026-10-06 shows no such command, so this plan does not add the job.

Success criteria: the support bar in Acceptance Criteria, and Guard Contract 4 green. Slice 2's PR closes #9608. Slice 1's PR does not.

## Files to Edit

Slice 1:

- `plugins/soleur/lib/harness.ts` — add `"cursor"` and the `routingInstructions` and `pollInstructions` arms. No env predicate.
- `plugins/soleur/lib/workflow-fidelity.ts` — `formatSkillRef` and `workflowFidelityInstructions` arms for `cursor`. `go` and `sync` stay `/go` and `/sync`. Every other name is `/soleur-<name>`.
- `plugins/soleur/commands/go.md` — Cursor text inside the three existing `harness-forms` regions, including the built-in `/plan`, `/help`, `/review`, and `/shell` names, the Soleur spellings, and the slice-1 limit. A new exempt site moves the pin of 21 and is still inside those three regions.
- `plugins/soleur/lib/pr-merge-poll.ts` — `behindSyncInstructions("cursor")` refuses the Claude plugin-root script, names no wait tool, and tells the operator the next action is another harness or a stop.
- `plugins/soleur/commands/help.md` — Cursor column lists `/go`, `/sync`, and `/soleur-<name>`, and names `/plan`, `/help`, `/review`, and `/shell` as names not to type.
- `plugins/soleur/test/harness.test.ts`
- `plugins/soleur/test/workflow-fidelity.test.ts`
- `plugins/soleur/test/components.test.ts` — manifest-dir equality gains `.cursor-plugin`.
- `plugins/soleur/test/harness-parity-tree.test.ts` — only if the `go.md` exempt count moves.
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/views.c4`

Slice 2, after the matching measurement:

- `plugins/soleur/lib/harness.ts` — `detectHarness`, after the four existing arms, and the four callers that have no harness argument. Under the marker they must not return the Skill tool or the Task tool.
- `plugins/soleur/scripts/emit-decision.sh` — the same marker list.
- `plugins/soleur/lib/pr-merge-poll.ts` — add a wait-tool name only when the capture contains one. The slice 1 refusal stays until then.
- `plugins/soleur/lib/harness-tool-map.ts` and `plugins/soleur/test/harness-tool-map.test.ts` — only when tool names were captured.
- `plugins/soleur/cursor/INSTRUCTIONS.md` — measured tools, polling, and hook sections.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — hook-engine surface sentence, when the registry exists. The embedded counts stay on their current clauses.

Do not edit in either slice: `TIER_MAPS`, `POPULATION_GLOBS`, `plugins/soleur/skills/{go,help,sync}/SKILL.md` unless a capture shows the loader executes those Devin shims, `plugins/soleur/hooks/hooks.json`, `grok-fidelity-gate.sh`, README, getting-started, comparison, FAQ, blog, battlecard, and the legal pages.

## Files to Create

Slice 1:

- `plugins/soleur/.cursor-plugin/plugin.json`
- `plugins/soleur/cursor/INSTRUCTIONS.md`
- `plugins/soleur/scripts/sync-cursor-name-map.ts` — `--check` prints `cursor-name-map ok` and exits 0 when the tree matches. No second shell.
- `plugins/soleur/test/cursor-name-map.test.ts`
- `plugins/soleur/test/cursor-loader-proof.test.ts`
- `plugins/soleur/cursor/commands/.gitkeep` — the directory must be committed. Git does not store an empty directory. The keeper is not `.md`, `.mdc`, `.markdown`, or `.txt`, because the plugin reference discovers commands under those suffixes.
- `plugins/soleur/cursor/hooks-empty.json` — `{ "hooks": {} }`
- `scripts/setup-cursor.sh`
- `.cursor-plugin/marketplace.json` at the repository root — marketplace `soleur`, owner `jikig-ai`, one plugin source `plugins/soleur`. Not a cursor.com submission.
- `knowledge-base/engineering/architecture/decisions/ADR-273-cursor-cli-harness.md` — ordinal provisional. The filename the architecture skill writes is the one that lands. This path is the planned placeholder.
- Generated `plugins/soleur/cursor/skills/<name>/SKILL.md` and `plugins/soleur/cursor/agents/soleur-<stem>.md`. Stem is the agent path with `/` replaced by `-`. The live census this plan measured is 103 skill folders and 67 agent files (c4-count-parity C8, 2026-10-06). The generator's output count is that census, not a hardcoded list. Pointers are relative to the plugin root.

Slice 2:

- No second hook file. Slice 2 fills `plugins/soleur/cursor/hooks-empty.json` only when the capture shows the CLI loads that path. Otherwise it adds nothing and does not call the plugin supported.
- `.claude/hooks/cursor-dispositions.tsv`
- `.claude/hooks/cursor-matcher-parity.test.sh`
- A date-stamped shape note under `plugins/soleur/cursor/`.

## Open Code-Review Overlap

Checked 2026-10-06. `gh issue list --label code-review --state open --limit 200` returned 87 issues. Standalone `jq --arg` searched each planned path inside those bodies.

- #8593 names `plugins/soleur/test/components.test.ts`. **Acknowledge.** This plan adds `.cursor-plugin` to the manifest-dir equality in that file. #8593 widens the unbounded-`gh`-enumeration detectors (`extractSearchProbes`, `GH_LIST_CMD`, `EXEC_SURFACE_GLOBS`, `HAS_LIMIT`). Different concern. The scope-out stays open. Its re-eval date is 2026-10-06 and is not this plan's work.

## Alternative Approaches Considered

- One spec, and docs after it works. Rejected. The operator chose two steps, with support only at the end.
- README in the same change. Rejected. Public sentences wait for the support bar. Filed as #9610.
- Copy Codex's `skills` array and Claude's `hooks.json`. Rejected. The documented field replaces discovery, and a copied registry would look installed.
- Hand-copy the skill tree. Rejected. ADR-245 requires a `Harness` member and a generator.
- Use `CURSOR_AGENT` in slice 1. Rejected. The terminal-tools page does not say the variable is CLI-only.
- Install a community pack (skillshare, agnix, or cursor-sync). Rejected. None is this repository's generator.
- Cursor IDE and Cloud Agents in this change. Rejected. IDE is #9611. Cloud Agents do not receive unsynced local skills.

## User-Brand Impact

Carried forward from the brainstorm of 2026-10-06. CPO reviewed that framing. CPO sign-off is required before work begins on the strength of that review. `soleur:engineering:review:user-impact-reviewer` runs at review time.

- **If this lands broken, the user experiences:** the Cursor CLI commands `/go`, `/sync`, and the `soleur-` prefixed skills and agents dead-end, or a session is told to call a tool that CLI does not have.
- **If this leaks, the user's workflow is exposed via:** a public sentence that claims support the product does not keep, or a hook envelope's `user_email` written into the repo.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one operator's dead-end session, or one false support sentence, is enough to treat the adapter as broken. An aggregate pattern would wait for many sessions.

- Artifact and vector: `/go` classifies into the wrong phase, so the operator's branch gets a draft PR for work they did not ask to build.
- Artifact and vector: hooks look installed and do not fire, so a commit to the default branch or a destructive command is not stopped.
- Artifact and vector: `/go` is registered twice and the operator cannot tell which body ran.

## Observability

The generator check is the liveness signal. It is a local test, not a host heartbeat. No new Sentry monitor and no new cron.

```yaml
liveness_signal:
  what: "sync-cursor-name-map.ts --check prints cursor-name-map ok and exits 0"
  cadence: "per pull request, on the test shard that runs plugins/soleur/test"
  alert_target: "a red test check on the pull request"
  configured_in: "plugins/soleur/scripts/sync-cursor-name-map.ts"
error_reporting:
  destination: "the test shard log for plugins/soleur/test"
  fail_loud: "non-zero exit and a line naming the drifted or missing stub"
failure_modes:
  - mode: "a generated stub is missing, extra, or hand-edited"
    detection: "sync-cursor-name-map.ts --check exits non-zero and names the path"
    alert_route: "the pull request test check"
  - mode: "the manifest points hooks at plugins/soleur/hooks/hooks.json"
    detection: "cursor-loader-proof.test.ts fails on that string"
    alert_route: "the pull request test check"
  - mode: "go is registered from commands/ and from cursor/skills/"
    detection: "cursor-loader-proof.test.ts fails when both directories contain go"
    alert_route: "the pull request test check"
logs:
  where: "GitHub Actions log of the test shard"
  retention: "GitHub Actions retains the job log; the assertion also lives in the committed test"
discoverability_test:
  command: bun plugins/soleur/scripts/sync-cursor-name-map.ts --check
  expected_output: "cursor-name-map ok"
```

`discoverability_test.command` has no `|`, `;`, `&`, `<`, `>`, `$`, or backtick. The script does not exist at plan time, so this command cannot return `cursor-name-map ok` yet. That absence is not a pass and not a fail of the probe. Work's first verification of this signal is the script's own test, after the script exists. Grep checks against files this plan has not created yet are expectations, not measured results. The public-doc and legal three-dot diffs were run on 2026-10-06 against `origin/main...HEAD` and both exited 0.

## Architecture Decision (ADR/C4)

Read on 2026-10-06: `knowledge-base/engineering/architecture/diagrams/model.c4`, `views.c4`, and `spec.c4`. `plugins/soleur/test/c4-count-parity.test.sh` passed, 13 of 13, including C8 (67 agents). This plan does not retouch those count clauses.

### ADR

Create, before product code, via `/architecture create 'Add a Cursor CLI plugin adapter'`. Provisional ordinal ADR-273. A 2026-10-06 census found ADR-272 on `origin/feat-one-shot-7122-community-monitor-output-allowlist` and `origin/feat-open-web-egress`. The same filename is on local `feat-agent-security-three-layers` and is not on `origin/feat-agent-security-three-layers`. `origin/main` stops at ADR-271. ADR-273 was the next free ordinal on origin heads that day. The pre-merge census reads `refs/heads` and `refs/remotes/origin`. It does not reserve 273. Decision: the Cursor CLI is a host runtime, with its own manifest, generated name map, and, after the capture, its own hook events in the empty plugin config. Status is `adopting` until slice 2 meets the support bar, then `accepted`. When that status flips, grep `knowledge-base/legal` for future-tense sentences about Cursor or the harness list and route hits to the CLO. Do not auto-edit legal pages. The title does not say supported. A sibling PR can take 273. On renumber, sweep this plan, `knowledge-base/project/specs/feat-cursor-harness-support/`, and the tasks file for the old ordinal in the same edit.

Checked actors and systems: the founder is already modeled. Codex, Devin, and Grok Build are external systems that load `platform.plugin`. Cursor CLI is not. No new data store. No new vendor account. The public marketplace is not an edge.

### C4 views

`model.c4`: add `cursorCli = system "Cursor CLI"` with `#external`. Description states local CLI only, load via `--plugin-dir`, hooks not run until the guard port is shown, and that the IDE and Cloud Agents are outside this element. Edges: `founder -> cursorCli` and `cursorCli -> platform.plugin`. No `github -> cursorCli` edge, because this plan adds no discovery CI job.

`views.c4`: include `cursorCli` in the context view and the containers view. `founder` and `platform.plugin` are already in both, which is the include rule that keeps the box connected.

`spec.c4`: unchanged. No new element kind.

Slice 2 amends the hook-engine description's harness-surface sentence when the registry file exists. That amendment does not edit the `github -> sentry` or agents count clauses.

After the edit, run `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, and `apps/web-platform/test/c4-render.test.ts`.

### Sequencing

The ADR is written at the start of slice 1 and describes the slice 2 target as `adopting`. It is not a follow-up issue.

## Guard Contract

### Guard 1 — Name map drift

**Property.** Every canonical skill folder and every canonical agent file has exactly one generated Cursor stub, and a hand edit of a stub fails the check.

**Assembly.** The chokepoint is `sync-cursor-name-map.ts`. It discovers skills by walking `plugins/soleur/skills/*/SKILL.md` and agents by walking `plugins/soleur/agents/**/*.md`. Both populations enter one writer. `--check` reruns that writer against the committed tree and is the only checker. A second writer, including a shell that only prints the ok line, is a defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one generated skill stub after a clean run | RED |
| 2 | Make the checker print ok and exit 0 without reading the tree (own dispatch, zero files checked) | RED |
| 3 | Add a second canonical skill after one compliant stub and do not regenerate | RED |
| 4 | Delete the assertion from the test and leave the checker always exiting 0 | RED |
| 5 | Regenerate after adding that second skill, with go and sync still unprefixed | PASS |

**Anchor.** The committed stub bytes must match a fresh run. A diff that edits a stub and the expected bytes together fails, because the checker compares the tree to a new run, not to a stored hash inside the stub.

### Guard 2 — One registration of /go

**Property.** `/go` and `/sync` each have one Cursor registration, and `/help` has none. Every other skill name is `soleur-` prefixed.

**Assembly.** The chokepoint is the manifest's `skills` and `commands` values, plus the generator's name function. Default discovery is the second path: an omitted or missing `commands` path loads `plugins/soleur/commands`. The proof test reads the manifest and both directories. A missing `cursor/commands` directory is RED. A file there whose suffix is `.md`, `.mdc`, `.markdown`, or `.txt` is RED. It does not call `rootsFor` and it does not reuse `ACKED_CROSS_ROOT_DUPES`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Point `skills` at `./skills` so canonical `plan` is visible | RED |
| 2 | Remove the manifest read from the proof test so it reports zero directories and exits 0 | RED |
| 3 | Add `commands/go.md` beside an existing `cursor/skills/go` | RED |
| 4 | Stub the proof to return success without opening plugin.json | RED |
| 5 | `cursor/skills/go` and `cursor/skills/sync` present, `cursor/commands/.gitkeep` present, that directory has no `.md`, `.mdc`, `.markdown`, or `.txt` file, `soleur-help` present, `help` absent | PASS |

### Guard 3 — Claude hooks file is not the Cursor registry

**Property.** Slice 1's manifest `hooks` value is a path to a hooks config file whose `hooks` object is empty, and that path is not `hooks/hooks.json`. The file is not a copy of the Claude or Devin registry.

**Assembly.** The manifest field and the file it names. The proof parses both. The plugin reference types `hooks` as a file path or an inline object, so a directory path fails this guard. A test that only reads `INSTRUCTIONS.md` for the words "hooks do not run" is not this guard. The instructions sentence is a second, weaker witness and does not satisfy the property alone.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Set `hooks` to `./hooks/hooks.json` | RED |
| 2 | Drop the hooks assertion so the test exits 0 on an empty manifest | RED |
| 3 | Add one event command to the empty `hooks` object after the field already points at that file | RED in slice 1. Slice 2 retires this empty-object row in the same change that fills the file from the capture, and the hook-parity guard replaces it. |
| 4 | Force the test's expected path to a constant that ignores plugin.json | RED |
| 5 | `hooks` is `./cursor/hooks-empty.json` and that file's `hooks` object is `{}` | PASS |

### Guard 4 — cursor only from the measured marker

**Property.** `detectHarness` returns `cursor` only when the measured CLI marker is present, and a Claude-shaped or Grok-shaped environment without that marker stays on its current arm.

**Assembly.** `detectHarness` in `plugins/soleur/lib/harness.ts`, the same marker list in `plugins/soleur/scripts/emit-decision.sh`, and the four no-argument emitters `formatSkillInvocation`, `invokeSkill`, `formatAgentSpawn`, and `spawnAgent`. Slice 1 does not add the predicate. Slice 2 adds the marker after the Claude, Grok, Codex, and Devin arms, in both marker sites, and arms the four emitters, in one change. A test of only one site is a failed guard. A return value of `cursor` with those four emitters still on the Skill tool or the Task tool is a failed guard.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Return `cursor` for an empty env | RED |
| 2 | Remove the env read so the function returns `cursor` for every input and the test still exits 0 | RED |
| 3 | Set the marker in `detectHarness` and leave `emit-decision.sh` on the four-marker list | RED |
| 4 | Delete the negative case that a `CLAUDECODE` env without the marker stays `claude` | RED |
| 5 | Empty env returns `unknown`. `CLAUDECODE` without the marker returns `claude`. `CLAUDECODE` plus the marker still returns `claude`. The measured marker, with `CLAUDECODE` unset, returns `cursor`, and the four no-argument emitters do not return the Skill tool or the Task tool | PASS |

Slice 2's hook parity guard is the same shape as `devin-matcher-parity.test.sh`: three claims (registry loads, matcher matches, body runs), a row for a missing working directory that fails closed, and a positive control that must fire. Its matrix is written in the shape note after the capture, before the registry file is added. Writing that matrix from the Devin file before the capture is a failed slice.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A setup step installs the plugin from the local path. A second machine can install from the git repository. Nothing is submitted to cursor.com." | `scripts/setup-cursor.sh`, Phase 1 | mapped |
| 2 | "On the Cursor CLI, `/go` and `/sync` resolve once. Other Soleur skills and agents resolve as `/soleur-<name>`, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`." | generator plus Guard 2 | mapped |
| 3 | "`detectHarness` returns `cursor` only for a marker measured on the Cursor CLI. Instructions for that session do not name the Skill tool, the Task tool, `run_subagent`, or AwaitShell." | Phase 2 and the `routingInstructions` arm | mapped |
| 4 | "Step 1 states that hooks do not run. A copied Claude or Devin `hooks.json` is not presented as a live Cursor registry." | Guard 3 and `cursor/INSTRUCTIONS.md` | mapped |
| 5 | "The plugin is called supported only when `/go` classifies, one pipeline skill finishes its gates, one agent spawn runs or is explicitly refused, and the full guard set fires on the Cursor CLI protocol." | Phase 2 success criteria | mapped |
| 6 | "README, getting-started, comparison FAQ, blog, and battlecard are unchanged by both slices." | Files to Edit exclusion list | mapped |
| 7 | "Legal wording, when a sentence is written: \"a Soleur plugin that runs in Cursor\" and \"not affiliated with or endorsed by Anysphere.\" The Terms parenthetical changes only after `harness.ts` has the `cursor` arm." | descoped from both slices | descoped — justification: the Terms edit is a later Tier 2 patch with CLO sign-off, and only after the arm exists. This plan writes no legal sentence. |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/setup-cursor.sh` and `--plugin-dir` | "A setup step installs the plugin from the local path. A second machine can install from the git repository. Nothing is submitted to cursor.com." | asked |
| Generator, `./cursor/skills`, `./cursor/agents` | "On the Cursor CLI, `/go` and `/sync` resolve once. Other Soleur skills and agents resolve as `/soleur-<name>`, including `/soleur-help`, `/soleur-plan`, and `/soleur-review`." | asked |
| `routingInstructions` and `formatSkillRef` arms | "Instructions for that session do not name the Skill tool, the Task tool, `run_subagent`, or AwaitShell." | asked |
| `detectHarness` predicate deferred to Phase 2 | "`detectHarness` returns `cursor` only for a marker measured on the Cursor CLI." | asked |
| `hooks` field and `cursor/hooks-empty.json` | "Step 1 states that hooks do not run. A copied Claude or Devin `hooks.json` is not presented as a live Cursor registry." | asked |
| Repo-root `.cursor-plugin/marketplace.json` | "A second machine can install from the git repository." | inferred — justification: the plugin reference says a git marketplace whose plugin is not at the repo root is listed in that file. `plugins/soleur` is not the repo root. The file is not a cursor.com submission. |
| `behindSyncInstructions("cursor")` refusal | "Instructions for that session do not name the Skill tool, the Task tool, `run_subagent`, or AwaitShell." | inferred — justification: the function takes a `Harness` and its default arm runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/sync-pr-behind.sh"`. A `cursor` member with no case hits that arm. |
| Phase 2 support bar | "The plugin is called supported only when `/go` classifies, one pipeline skill finishes its gates, one agent spawn runs or is explicitly refused, and the full guard set fires on the Cursor CLI protocol." | asked |
| Public-doc exclusion | "README, getting-started, comparison FAQ, blog, and battlecard are unchanged by both slices." | asked |
| ADR-273 and the C4 `cursorCli` element | The spec requires an architecture decision before product code. The create title is "Add a Cursor CLI plugin adapter" so the record does not say supported before slice 2. | inferred — justification: ADR-245 and the plan architecture gate require a Harness member to be recorded in an ADR and in the C4 model in the same change. The three existing CLI hosts are already elements. |
| `sync-cursor-name-map.ts --check` and the four guards | "the full guard set fires on the Cursor CLI protocol" | inferred — justification: a guard that cannot be driven red does not enforce the support bar. The drift pin rots without `--check`. |
| Leaving `TIER_MAPS` without a Cursor row | "The canonical skill tree stays the source." | inferred — justification: Codex and Devin already inherit by absence. Adding a model id would invent a Cursor catalog slug the ask does not name. |
| `commands` directory with no markdown | "`/go` and `/sync` resolve once" | inferred — justification: omitting `commands` loads `plugins/soleur/commands/`, which registers `/help` and a second `/go`. |
| Shape note and disposition ledger | "the full guard set fires on the Cursor CLI protocol" | inferred — justification: ADR-223's ledger is the record that a matcher matched. A registry file alone does not show the body ran. |

### Split Assessment

- Subsystems touched: 4 — `plugins/soleur`, `scripts`, `knowledge-base`, `.claude`
- Planned files: 194 | Estimated changed lines: 2600
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — slice 1 is one PR (manifest, generator output, instruction arms, setup script, ADR, C4). Slice 2 is a second PR (measured marker, hook registry, disposition ledger, support bar) and is the PR that closes #9608. The generated stubs stay in slice 1 because the manifest's `skills` path must exist for the loader. They are one generator run, not a third PR.

The 194 count is 24 hand-written paths plus 103 skill stubs plus 67 agent stubs. The 2600 line estimate is about 12 lines per stub plus about 600 lines of hand edits. The extra hand paths are the empty hooks file and the repo-root marketplace file.

## Acceptance Criteria

### Functional Requirements

- [ ] `scripts/setup-cursor.sh` resolves `plugins/soleur` from its own path with `BASH_SOURCE`, passes that absolute path to `--plugin-dir`, and does not call `readlink -f`, `timeout`, `sed -i`, or `date -d`. When `agent` is missing it prints that fact and exits non-zero. It does not prompt for a token and it does not open an install URL. Its stdout names the next command and states that slice 1 does not classify the session as `cursor` and does not run hooks. It does not run `agent plugin marketplace add`, it does not create a `~/.cursor/plugins/local` symlink to this checkout, and it does not submit anything to cursor.com.
- [ ] On a generated tree, `go` and `sync` each appear once, unprefixed, and their stubs point at `commands/go.md` and `commands/sync.md`. `help` does not appear. `soleur-help` points at `commands/help.md` and does not contain `Detect the active harness as Devin`. `soleur-plan` and `soleur-review` appear, and those three stubs set `disable-model-invocation: true`. Every other canonical skill and agent appears as `soleur-<name>`. Agent `agents/engineering/cto.md` is `soleur-engineering-cto`. No stub path starts with `plugins/soleur/`. A copied description that contains a colon is a quoted YAML scalar.
- [ ] `formatSkillRef` for `cursor` returns `/go`, `/sync`, `/soleur-help`, `/soleur-plan`, and `/soleur-review` for those five names. `routingInstructions("cursor")` contains `/go` and `/soleur-plan`, and it does not contain `/soleur-go`, `/soleur:`, `Skill`, `Task`, `run_subagent`, or `AwaitShell`.
- [ ] Slice 1's `plugin.json` `hooks` value is `./cursor/hooks-empty.json`, that file's `hooks` object is `{}`, and `cursor/INSTRUCTIONS.md` states that this plugin file registers no hook events and that slice 1 does not classify the session as `cursor`.
- [ ] `behindSyncInstructions("cursor")` does not contain `CLAUDE_PLUGIN_ROOT`, does not name a wait tool, and names the next action as another harness or a stop.
- [ ] `.cursor-plugin/marketplace.json` at the repo root lists one plugin whose source is `plugins/soleur`. `scripts/setup-cursor.sh` does not run `agent plugin marketplace add`. The documented failure exit is clone plus `scripts/setup-cursor.sh`. Slice 1 does not assert what the installed CLI prints.
- [ ] Until the slice 2 predicate lands, empty env still returns `unknown`, and a `CLAUDECODE` env without the marker still returns `claude`. After it lands, the marker is tested after the four existing arms. `CLAUDECODE` plus the marker returns `claude`. The marker with `CLAUDECODE` unset returns `cursor`, and the four no-argument emitters do not return the Skill tool or the Task tool.
- [ ] The plugin is called supported only when slice 2's committed shape note quotes `/go` classifying, one pipeline skill finishing its gates, one agent spawn running or refusing in words, and each guard in this contract firing. A live re-run is not the criterion.
- [ ] README, getting-started, comparison FAQ, blog, and battlecard have an empty three-dot diff in both PRs: `git diff --quiet origin/main...HEAD -- README.md plugins/soleur/README.md plugins/soleur/docs/pages/getting-started.njk plugins/soleur/docs/pages/compare-soleur-vs-cursor.njk plugins/soleur/docs/pages/compare-soleur-vs-devin.njk plugins/soleur/docs/pages/blog.njk plugins/soleur/docs/blog knowledge-base/sales/battlecards`. A generated `knowledge-base/INDEX.md` row and `knowledge-base/project/specs/feat-cursor-harness-support/tasks.md` are pipeline writes and sit outside that claim.
- [ ] Neither PR edits `docs/legal/` or `plugins/soleur/docs/pages/legal/`. Proof is `git diff --quiet origin/main...HEAD -- docs/legal plugins/soleur/docs/pages/legal`.

### Non-Functional Requirements

- [ ] Model tier for `cursor` stays `inherit` by absence from `TIER_MAPS`.
- [ ] Generated files sit outside `POPULATION_GLOBS`. `harness-parity` stays green without a Cursor exemption for those files.
- [ ] The slice 1 PR carries `semver:minor`. Version files are not edited on this branch.
- [ ] No Cursor token, Doppler key, or `user_email` from a hook envelope is written to the tree.

### Quality Gates

- [ ] Guard Contract tests follow RED then GREEN.
- [ ] `plugins/soleur/test/c4-count-parity.test.sh` stays green after the `cursorCli` element.
- [ ] The ADR filename added in slice 1 does not reuse an ordinal already present under `knowledge-base/engineering/architecture/decisions` on `origin/main` at add time. The 2026-10-06 probe found ADR-273 free on origin heads. A later collision is a renumber of this plan, the spec directory, and the tasks file in the merge edit. That renumber is risk mitigation, not a result an unmerged sibling can flip on an unchanged diff.

## Domain Review

**Domains relevant:** product, engineering, legal, marketing

Carried forward from the 2026-10-06 brainstorm. Leaders are not re-spawned. No specialist beyond those four was required.

### Product

**Status:** reviewed
**Assessment:** Project-local adapter, one load path, honest refusals. No public sentence until the support bar. The operator narrowed the runtime to the CLI and required the full guard set, in two steps.

### Engineering

**Status:** reviewed
**Assessment:** Cursor cannot load this plugin unchanged. Add a `Harness` member and a generator. Measure before an env predicate, a hook binding, or a skills array. Model tier inherits. The plan records the documented replace rule and still requires a live capture before the predicate.

### Legal

**Status:** reviewed
**Assessment:** Draft, not legal advice. An in-repo adapter is the same class as Codex, Devin, and Grok. No Anysphere processor row. Marketplace publish is a different contract and is out of scope. The Terms parenthetical stays out of both slices.

### Marketing

**Status:** reviewed
**Assessment:** No public sentence and no comparison, battlecard, getting-started, or README edit. After slice 2 is green, one FAQ sentence is the only public correction, and only if a public line is still wanted. That sentence is #9610, not this plan.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer (Phase 3). No page, so the design lead and the copywriter were not invoked.
**Skipped specialists:** soleur:product:design:ux-design-lead, soleur:marketing:copywriter — no page, layout, form, or component is in the file list
**Pencil available:** no UI surface in the file list
**Journey gaps absorbed:** the setup script prints the next command and the slice-1 limit, and it does not prompt for a token. The git install is a separate step with a clone-and-run-local exit. `commands/go.md` names the built-in slash collisions. `behindSyncInstructions("cursor")` does not use the Claude plugin root. A session without the measured marker stays `unknown`. That last case is not given a second Cursor signal.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the manifest skills path is `./skills`, when the loader proof runs, then it fails.
- Given a clean generator run, when one stub is deleted, then `sync-cursor-name-map.ts --check` exits non-zero and names the path.
- Given `formatSkillRef` for `cursor`, when `go`, `sync`, `help`, `plan`, and `review` are rendered, then the results are `/go`, `/sync`, `/soleur-help`, `/soleur-plan`, and `/soleur-review`.
- Given an empty environment, when `detectHarness` runs before slice 2, then the result is `unknown`.
- Given `CLAUDECODE` set and the measured marker unset, when `detectHarness` runs after slice 2, then the result is `claude`.

### Edge Cases

- Given `cursor/commands/go.md` is added next to `cursor/skills/go`, when the proof runs, then it fails.
- Given one event command is added to `cursor/hooks-empty.json`, when the proof runs, then it fails.
- Given `--check` is replaced with a path that prints `cursor-name-map ok` without reading the tree, when the suite runs, then the suite fails.
- Given the captured hook envelope has no working directory, when the slice 2 registry is evaluated, then the disposition is fail-closed and the plugin is not called supported.

### Integration Verification (for `soleur:qa`)

Slice 2's CLI session is the integration check. Slice 1 has no live CLI proof and does not claim one. No browser route and no HTTP API are in this change.

## Success Metrics

- Slice 1 merges with Guards 1, 2, and 3 green and the public-doc diff empty.
- Slice 2 closes #9608 only after the support bar is observed on a Cursor CLI session.
- #9610 and #9611 stay open and blocked by #9608.

## Dependencies & Prerequisites

- Draft PR #9598 on `feat-cursor-harness-support` is the PR slice 1 uses. It stays draft until slice 1 is reviewed.
- A Cursor CLI on a machine that can start a session is a slice 2 prerequisite. It is not a slice 1 prerequisite.
- `agent plugin marketplace add` is cited from the changelog of 2026-07-13. The repo-root marketplace file is the documented source list for a plugin that lives at `plugins/soleur`. Slice 2 confirms the command with `--help` on the installed CLI before that git step is called verified on that machine. The setup script does not run it.

## Risk Analysis & Mitigation

- Binding `CURSOR_AGENT` because the docs name it. Mitigation: Guard 4's negative case, and no predicate in slice 1.
- Treating the documented hook JSON as the envelope. Mitigation: slice 2 starts with a capture. The docs are the hypothesis.
- Default discovery loading `hooks/hooks.json`. Mitigation: Guard 3.
- Pointing `go` and `sync` stubs at the Devin shim skills. Mitigation: those two stubs point at `commands/go.md` and `commands/sync.md`.
- Calling the plugin supported at the end of slice 1. Mitigation: the instructions file and both PR bodies keep the support bar on slice 2.
- A sibling ADR taking ordinal 273. Mitigation: re-run the origin-head filename census immediately before merge, and sweep this plan, the spec directory, and the tasks file in the same edit.

## Resource Requirements

Two pull requests on the existing worktree. No new host, secret, or vendor account. Slice 2 needs one Cursor CLI session for the capture. The generated tree is about 170 files from one script.

## Future Considerations

- #9611 is the IDE agent, after the CLI marker is known, so the IDE does not become `cursor` by accident.
- #9610 is the one FAQ sentence, after the support bar, and only if a public line is still wanted.
- #9609 is the checklist for the next host, revisited after slice 1 merges.
- A headless skills list, if Cursor adds one, is the trigger for a non-required `harness-discovery` job. It stays off `grok-fidelity`.

## Documentation Plan

`plugins/soleur/cursor/INSTRUCTIONS.md` says this plugin registers no hook events. `scripts/setup-cursor.sh` prints the next command and the slice-1 limit. README, getting-started, comparison, FAQ, blog, battlecard, and legal pages are unchanged. The ADR and the C4 element are the architecture record.

## References & Research

### Internal References

- ADR-245, ADR-223, ADR-224, ADR-179, ADR-226, ADR-215
- `plugins/soleur/lib/harness.ts` `Harness` union
- `plugins/soleur/scripts/sync-grok-agent-compat.ts` as the generator shape to follow without copying its Claude manifest write
- `scripts/setup-devin.sh` and `scripts/setup-codex.sh` as the local-path setup shape
- Brainstorm `knowledge-base/project/brainstorms/2026-10-06-cursor-harness-support-brainstorm.md`
- Spec `knowledge-base/project/specs/feat-cursor-harness-support/spec.md`

### External References

- <https://cursor.com/docs/plugins>
- <https://cursor.com/docs/reference/plugins>
- <https://cursor.com/docs/skills>
- <https://cursor.com/docs/hooks>
- <https://cursor.com/docs/cli/reference/slash-commands>
- <https://cursor.com/docs/cli/reference/parameters>
- <https://cursor.com/docs/cli/changelog>
- <https://cursor.com/docs/agent/tools/terminal>
- <https://cursor.com/terms-of-service> (last updated September 3, 2026)

### Related Work

- #9608, #9611, #9610, #9609
- #9598
- #6320 and #8299 stay closed
