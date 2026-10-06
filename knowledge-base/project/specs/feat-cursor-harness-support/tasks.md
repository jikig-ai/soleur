# Tasks: Cursor CLI harness support

Issue #9608. Lane `cross-domain`, carried from `spec.md`. Slice 1 uses draft PR #9598 and does not close the issue. Slice 2 is a second PR whose body contains `Closes #9608`.

## Phase 1: Setup

- [ ] 1.1 Stay on `feat-cursor-harness-support` in `.worktrees/feat-cursor-harness-support`. Do not open a second worktree. Do not mark #9598 ready.
- [ ] 1.2 Re-run the ADR filename census over `refs/heads` and `refs/remotes/origin`. Then run `/architecture create 'Add a Cursor CLI plugin adapter'`. The title does not say supported. Status stays `adopting` until slice 2 meets the support bar. Record the census in the decision body. If the ordinal is taken, renumber this plan, the spec directory, and this tasks file in that same edit.

## Phase 2: Core Implementation

- [ ] 2.1 Slice 1 manifest and install
  - [ ] 2.1.1 Add `plugins/soleur/.cursor-plugin/plugin.json` with `skills` `./cursor/skills`, `agents` `./cursor/agents`, `commands` `./cursor/commands`, and `hooks` `./cursor/hooks-empty.json`.
  - [ ] 2.1.2 Add `plugins/soleur/cursor/hooks-empty.json` as `{ "hooks": {} }`.
  - [ ] 2.1.3 Add `plugins/soleur/cursor/commands/.gitkeep`. No `.md`, `.mdc`, `.markdown`, or `.txt` file in that directory.
  - [ ] 2.1.4 Add repo-root `.cursor-plugin/marketplace.json` named `soleur`, owner `jikig-ai`, one plugin source `plugins/soleur`.
  - [ ] 2.1.5 Add `scripts/setup-cursor.sh`. Resolve the plugin directory with `BASH_SOURCE`. Do not call `readlink -f`, `timeout`, `sed -i`, or `date -d`. When `agent` is missing, print that and exit non-zero. Print the absolute `--plugin-dir` line and the slice-1 limit. Do not prompt for a token, open an install URL, run marketplace add, or symlink into `~/.cursor/plugins/local`.
- [ ] 2.2 Slice 1 name map
  - [ ] 2.2.1 Add `plugins/soleur/scripts/sync-cursor-name-map.ts`. `--check` prints `cursor-name-map ok` and exits 0 only after it reads the tree.
  - [ ] 2.2.2 Point `go`, `sync`, and `soleur-help` at `commands/go.md`, `commands/sync.md`, and `commands/help.md`. Point every other skill at `skills/<folder>/SKILL.md`. Paths are relative to the plugin root.
  - [ ] 2.2.3 Name each agent from its path under `agents/` with `/` replaced by `-`. `agents/engineering/cto.md` becomes `soleur-engineering-cto`. Fail `--check` when two sources share one output name.
  - [ ] 2.2.4 Start every stub with the Cursor stop header. Copy a canonical `description` into a quoted YAML scalar. Set `disable-model-invocation: true` on the generated `plan`, `help`, and `review` stubs.
- [ ] 2.3 Slice 1 instruction arms
  - [ ] 2.3.1 Add `"cursor"` to the `Harness` union. Do not change `detectHarness`.
  - [ ] 2.3.2 Arm `routingInstructions`, `pollInstructions`, `workflowFidelityInstructions`, `formatSkillRef`, and `behindSyncInstructions`. `go` and `sync` render as `/go` and `/sync`. Every other name renders as `/soleur-<name>`.
  - [ ] 2.3.3 The behind-sync and poll arms are one short stop: no wait tool, no `CLAUDE_PLUGIN_ROOT`, next action is another harness or a stop.
  - [ ] 2.3.4 Put the Cursor spellings and the slice-1 limit inside the three existing `harness-forms` regions in `commands/go.md`. Add the Cursor column to `commands/help.md`.
  - [ ] 2.3.5 Write `plugins/soleur/cursor/INSTRUCTIONS.md`. It says this plugin file registers no hook events, slice 1 does not classify the session as `cursor`, and `.claude/settings.json` is unmeasured.
- [ ] 2.4 Slice 1 C4
  - [ ] 2.4.1 Add `cursorCli` to `model.c4` as an external system, with `founder -> cursorCli` and `cursorCli -> platform.plugin`. Include it in the context and containers views. Do not add a `github -> cursorCli` edge. Do not retouch the embedded count clauses.
- [ ] 2.5 Slice 2, after the capture, on a second PR
  - [ ] 2.5.1 Record which hook sources the CLI loaded, then the marker, the envelope, the working directory, and the tool names. `CURSOR_AGENT` is a candidate until a CLI session and a non-CLI process are both measured.
  - [ ] 2.5.2 Add the predicate after the Claude, Grok, Codex, and Devin arms. `CLAUDECODE` plus the marker still returns `claude`. Arm `emit-decision.sh` and the four no-argument emitters in that same change.
  - [ ] 2.5.3 Fill `plugins/soleur/cursor/hooks-empty.json` only if the capture shows the CLI loads that path. Otherwise add no second registry and do not call the plugin supported. Do not add a repo-level `.cursor/hooks.json`.
  - [ ] 2.5.4 Mark `.claude/settings.json` already-fires or dead before copying any guard command from it. Do not store `user_email`.
  - [ ] 2.5.5 Write the shape note, the disposition ledger, and the matcher parity test from the capture. The shape note is what the support bar quotes.

## Phase 3: Testing

- [ ] 3.1 Drive Guards 1, 2, and 3 red, then green, in slice 1. Guard 3's empty-object row is slice 1 only. Slice 2 retires it in the same change that fills the hooks file.
- [ ] 3.2 Drive Guard 4 red, then green, in slice 2, including the four emitters and the `CLAUDECODE`-plus-marker case.
- [ ] 3.3 Run `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, and `apps/web-platform/test/c4-render.test.ts` after the C4 edit.
- [ ] 3.4 Run `git diff --quiet origin/main...HEAD` on the public-doc paths and on `plugins/soleur/docs/pages/legal`. Both stay empty.
- [ ] 3.5 Slice 1's PR carries `semver:minor` and does not edit version files. Slice 2's PR body closes #9608 only after the shape note quotes the support bar.
- [ ] 3.6 `bun plugins/soleur/scripts/sync-cursor-name-map.ts --check` prints `cursor-name-map ok`. A deleted stub makes that same command exit non-zero and name the path.
- [ ] 3.7 `formatSkillRef` for `cursor` returns `/go`, `/sync`, `/soleur-help`, `/soleur-plan`, and `/soleur-review` for those five names.
