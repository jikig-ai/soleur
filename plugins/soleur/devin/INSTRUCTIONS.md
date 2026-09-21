# Soleur on Devin CLI

These mappings apply when running Soleur instructions in Devin CLI. Keep the
canonical skill phases, decision gates, and completion checks. Tool names in
those instructions describe intent; use the tools actually available in the
current Devin session.

## Paths and entry points

The installed plugin root is available via `${CLAUDE_PLUGIN_ROOT}` (Devin inherits this from Claude plugin format compatibility). If the variable is unset in the session, resolve the installed root from the Devin plugin cache — `~/.local/share/devin/cli/plugins/cache/<source-slug>/0.0.0-unversioned` — and verify it by checking `.claude-plugin/plugin.json` carries `"name": "soleur"`.
Resolve Soleur's `plugins/soleur/...` references against that root; resolve project
files and `knowledge-base/` against the user's current project or worktree.
Never search another harness's cache for the plugin. In shell examples,
set `CLAUDE_PLUGIN_ROOT` to the verified installed root for that command.
Plugin hooks receive that variable automatically; ordinary shell tools need
not inherit a plugin hook's environment.

Install the plugin from the monorepo subfolder:

```bash
devin plugins install jikig-ai/soleur#plugins/soleur -y
```

You must be signed in (`devin auth login`) for plugin installation. Use `-y` to skip the confirmation prompt. The first install may take a few minutes because Devin clones the `jikig-ai/soleur` repository to reach the `plugins/soleur` subfolder.

The `owner/repo#subdir` shorthand above is a `devin plugins install` form only. In a manifest position (`.devin/config.json` `requiredPlugins`) it parses as a local path relative to the repo root and fails with "is not a directory". The full-URL string form (`"https://github.com/jikig-ai/soleur#plugins/soleur"`) resolves locally but is broken in cloud: the cloud resolver passes the whole string — `#subdir` fragment included — to the `git-manager.devin.ai` proxy as the repository path and the fetch 404s (measured 2026-09-17 on a `/handoff` session and a DRS sandbox, #8172). Use the `git-subdir` object form, which registers and resolves at repo level on both surfaces:

```jsonc
// .devin/config.json
{
  "requiredPlugins": [
    {
      "source": "git-subdir",
      "url": "https://github.com/jikig-ai/soleur.git",
      "path": "plugins/soleur"
    }
  ]
}
```

If the remote install hangs or fails, clone the repository and install from the local path:

```bash
git clone https://github.com/jikig-ai/soleur.git
devin plugins install --local ./soleur/plugins/soleur -y
```

Use `/soleur:go <intent>`, `/soleur:sync`, and `/soleur:help` as Devin slash commands.
These are skill invocations, not shell commands.

## Updating the plugin

Devin caches plugin content locally. To pull the latest `main` from the monorepo source, run:

```bash
devin plugins update soleur
```

To refresh every installed plugin at once:

```bash
devin plugins update
```

For local-folder installs (`--local`), edits are reflected in the next session with no `update` needed.

If you see a transient warning such as "plugin ... is in your settings but its content could not be fetched; it will be retried automatically", the cloud-side fetcher is having trouble reaching GitHub. The CLI copy usually still works; run `devin plugins update soleur` again after a moment, or switch to a `--local` install if the remote source stays unreachable.

## Tools

| Soleur instruction | Devin execution |
| --- | --- |
| Read / Glob / Grep | read, grep, glob tools |
| Write / Edit | write, edit tools |
| Bash / Shell | exec tool |
| Skill `soleur:<name>` | Slash command `/soleur:<skill>` (e.g. `/soleur:one-shot`, `/soleur:brainstorm`) |
| Task / Agent / spawn_subagent | run_subagent tool |
| AskUserQuestion | ask_user_question tool |
| TodoWrite / TodoRead | todo_write tool |
| Monitor / AwaitShell / TaskOutput | get_output to poll a backgrounded shell's output; for wait-until-event watches (CI settle, PR merge state) a background `run_subagent` exit-coded poll loop — see **Polling / watches** below |
| WebSearch / WebFetch / ToolSearch | web_search, webfetch tools |
| Workflow scripts | Translate orchestration to available tools; do not execute Claude tool calls as shell JavaScript |

Soleur skills are exposed as Devin slash commands (`/soleur:<skill>`). When a slash command is invoked, Devin loads the skill's `SKILL.md` and treats its body as the prompt. Follow the skill's full workflow and referenced files; do not stop after reading it, reproduce it selectively, or ask the user to run the next stage.
Treat `$ARGUMENTS` as the supplied request (the text following the slash command), never as an environment variable that needs shell interpolation.

## Cloud Mode (Devin Cloud sessions)

Soleur runs in two Devin environments with different enforcement surfaces:

| Surface | Local CLI/Desktop | Devin Cloud session |
| --- | --- | --- |
| Skills (`/soleur:*`) | yes | yes — measured 2026-09-15 (both arms): ~95 skills loaded from the plugin cache |
| Plugin `AGENTS.md` rules | yes | yes — measured: injected as always-on `<rules>` blocks |
| MCP servers | yes | yes (auth via the web-app connection) — measured: listed in-session |
| Plugin subagents (`agents/**/*.md`) | yes | **no — plugin-defined agents absent** (documented limitation, corroborated both arms). Built-in fan-out substrate exists in the web-app arm (`run_subagent`, `run_workflow`) but not the Soleur roster |
| `ask_user_question` | yes | **no — tool absent**; `message_user` (`user_question`) is blocking with no auto-approve — an unanswered ask stalls the session indefinitely (fail-closed) |
| Plugin hooks: `SessionStart` / `SessionEnd` | yes | **no — never fire in cloud** |
| Plugin hooks: `command` type (PreToolUse, PostToolUse, Stop) | yes | **no — measured absent (both arms)**: `matcher: ""` catch-all produced nothing; docs.devin.ai initially claimed cloud dispatch, then was corrected to scope hooks local-only + "best effort, fail open" (matches measurement) |
| Repo-level hooks (`.devin/config.json`, `.claude/settings.json`) | yes | **no — measured absent (both arms)**: SessionStart `additionalContext` never reached the session; catch-all marker test produced nothing |
| `.devin/config.json` `requiredPlugins` | yes | **measured honored** — repo key registered `scope: "repo"` from each repo cloned at session start; `git-subdir` object form resolves, full-URL `#subdir` string form 404s through the cloud git-manager proxy (see install section) |

*Evidence class:* rows marked "measured" come from 2026-09-15 probe arms —
a `devin cloud drs` sandbox and a user-facing web-app session — plus the
2026-09-17 residual arms (two `/handoff` sessions, three DRS sandboxes)
(`cloud-probe.md`); `PostCompaction` remains unmeasured — tracked at #8172.

**Detection:** `bash "${CLAUDE_PLUGIN_ROOT}/scripts/cloud-detect.sh"` prints
`local` or `not-local:<reason>` (`sentinel-absent`, `foreign-host`,
`non-plugin-source`, `malformed`, `conflicting-evidence`, `no-devin-env`). If
`CLAUDE_PLUGIN_ROOT` is unset — measured: cloud exec shells export only
`DEVIN_DIR` + `DEVIN_DISABLE_HISTEXPAND`, no `CLAUDE*`/`SOLEUR*` vars — resolve
the plugin ROOT first, then name the script relative to it. Search the two
managed plugin caches, `"$HOME/.local/share/devin/cli/plugins/cache"` and
`/opt/.devin/plugins` (whose lock file is `/opt/.devin/plugins/lock.json`),
skipping either unless `[ -d "$d" ]`, and select by IDENTITY:

```sh
MANIFEST="$(find "$d" -path '*/.claude-plugin/plugin.json' \
  -exec grep -l '"name"[[:space:]]*:[[:space:]]*"soleur"' {} + 2>/dev/null | head -1)"
ROOT="${MANIFEST%/.claude-plugin/plugin.json}"
```

One resolution serves both consumers — `$ROOT/scripts/cloud-detect.sh` and
`$ROOT/scripts/precommit-guard.sh`. Selecting by the script's BASENAME instead
would accept any directory under the cache that happens to hold a file with
that name, and then execute it. The identity check is a shape check, not
authentication: a planted `{"name":"soleur"}` manifest passes it (ADR-179 A11).
It buys consistency with `/soleur:go`'s own resolver and defence-in-depth.

The classifier is sentinel-based: the SessionStart hook writes
`.devin/soleur-local-session` (`{host, ts, hook_source}`) on local sessions,
and SessionStart never fires in cloud. A session is `local` only when the
sentinel exists, its `host` matches the current hostname, `hook_source` is
`plugin`, AND no cloud-only env marker is present. `DEVIN_DIR`/
`DEVIN_DISABLE_HISTEXPAND` are measured cloud-only: a valid plugin sentinel on
a box carrying them classifies `not-local:conflicting-evidence` — the
upstream-convergence arm, so a future partial dispatch of plugin hooks in
cloud (#8160) fails closed instead of reading as local. Every other outcome
fails closed to `not-local` — a repo-level SessionStart firing in cloud
produces a `non-plugin-source` sentinel, not a false local.

`not-local:no-devin-env` is the one reason that is NOT cloud: it means no
sentinel and no Devin env markers — i.e. probably not a Devin session at all
(a Claude Code session, for example). Treat it like `local`: proceed normally,
no banner, no cloud contract.

**In a `not-local` session, all four rules apply:**

1. **Banner.** Emit `cloud-detect.sh --banner` (stderr) at the start of
   pipeline work so the degraded capability state is visible, not silent.
2. **Sequential fallback.** Plugin subagents do not exist in cloud. A skill
   that fans out executes each role definition sequentially inline, with the
   same definition, and discloses: deliverables and PR trailers carry
   `Reviewed-Coverage: sequential-fallback` (via
   `emit-review-trailer.sh --mode sequential-fallback`). Never claim an
   independent review ran when it did not. `/ship` blocks a
   `single-user incident` plan carrying `sequential-fallback` coverage unless
   the operator explicitly acknowledges.
3. **Acknowledgement gate.** Before any secrets read, production mutation,
   Doppler action, Terraform production action, mutating GitHub API call, or
   other credential-bearing operation, require an explicit session-scoped
   acknowledgement via `message_user` — the only ask primitive that exists in
   cloud (`ask_user_question` is absent). The ack lives in conversation
   context only — no persisted ack file (a stale file replays into a new
   session). `message_user` blocks: if it returns an answer, proceed; if the
   session is unattended (`--headless` or no operator channel), the call
   stalls indefinitely — that IS the defer. Do not substitute an
   in-transcript "proceeding unless you object"; defer the secrets/prod step
   and document the alternative.
4. **Absent guardrails.** SessionStart rule injection and any hook that does
   not fire are gone. The sole restored check is commit-on-main: every marked
   skill's cloud-mode block instructs running
   `scripts/precommit-guard.sh "<command>"` before any `git commit`, and
   work/ship/one-shot carry the same instruction on their commit paths. Every
   other repo guardrail is **not restored** in cloud — treat the session as
   running without hook backstops.

**Guardrails NOT restored in cloud** (repo `.claude/hooks/`; cloud execution
undocumented, absent entirely in user repos): prod-write-defer-gate,
worktree-write-guard, git-commit-secret-scan, guardrails (all arms except the
commit-on-main check precommit-guard.sh restores), memory-backstop,
iac-plan-write-guard, freeze-lock, brand-hex-commit-gate, context-reviewed-gate,
doppler-secrets-delete-redirect, ship-*-gate family, pre-merge-rebase,
monitor-supersede-guard, post-dispatch-watch-gate, and the remaining
`.claude/hooks/` corpus. The DONE-marker stop-gate is likewise not restored —
it reads hook-stdin transcript data a standalone script cannot see.

**Upstream requests** (capability gaps only Cognition can close):

- **#8160** — plugin subagents (`agents/**/*.md`) and plugin hooks in cloud
  sessions. Probe-measured 2026-09-15 on **both** arms (sandbox + user-facing
  web-app): NO hooks dispatch anywhere — repo `.devin/config.json`,
  `.claude/settings.json`, and plugin `hooks.json` all inert, including a
  `matcher: ""` catch-all. Cloud is a no-hook environment. Plugin-defined
  agents absent (documented limitation); built-in `run_subagent` exists in
  the web-app arm but cannot load the Soleur roster. The request should
  cover ALL hook surfaces, not just SessionStart/SessionEnd. Filing package:
  `knowledge-base/project/specs/feat-devin-upstream-asks-posture/upstream-asks.md`;
  submission state is tracked on #8160. Detection:
  `scheduled-devin-docs-drift.yml` watches the docs.devin.ai surfaces where a
  capability would become visible (disposable — teardown on #8160 close).
- **`requiredPlugins` `url`+`#subdir` resolver bug** — measured 2026-09-17
  (#8172): a full-URL string requirement carries its `#plugins/soleur`
  fragment verbatim into the `git-manager.devin.ai` fetch path and 404s
  ("repository not found"); the same string resolves locally. The object
  form (`{"source":"git-subdir","url":...,"path":...}`) registers and
  resolves at repo level in cloud. Repo-level `requiredPlugins` itself is
  confirmed honored in cloud — registered `scope: "repo"` per repo cloned
  at session start. Fix: strip the fragment / map the string form onto the
  `git-subdir` source in the cloud resolver.
- **`requiredPlugins` marginal effect** — repo-level key is documented
  (plugins overview §Inheritance level 3), but the account's managed manifest
  already installs Soleur, masking the marginal effect; a clean-account arm
  remains open (#8172).
- **`/handoff` does not deliver the declared working state** — measured
  2026-09-17 (#8172): the session checkout came from the warm blueprint
  image on `main`, not the handed branch, and no uncommitted state
  (tracked diff, untracked, gitignored `.devin/` files) materialized on the
  filesystem — `git status` clean. CLI docs claim handoff "checks out the
  branch you're on"; measured otherwise.
- **`ask_user_question` in cloud** — tool absent; `message_user` is
  blocking-only and stalls indefinitely when unanswered. If an interactive
  question primitive is added to cloud, its unattended semantics need
  documenting (auto-approve would fail the ack gate open).
- **`PostCompaction` in cloud** — documented-capable but unmeasured (no
  dispatcher observed for any other event; the 2026-09-17 handoff arm
  registered a marker on the probe branch but the checkout came from
  `main`, so the binding was never active — still needs an arm where
  compaction actually fires, #8172).

## Domain agents

Canonical definitions live in `agents/<domain>/**/*.md`. Find an agent by
its qualified ID (`soleur:engineering:review:security-sentinel` maps to
`agents/engineering/review/security-sentinel.md`) or its frontmatter name.
Read the definition before delegation. Spawn using the available tool's
actual schema, passing its absolute definition path, this instruction file,
the task, and the current worktree path. Do not pass a Claude registry ID as
a Devin agent type. Inherit the session model and permission policy; Claude
model aliases are not Devin model identifiers.

If subagents are unavailable, execute the requested role sequentially with
the same definition and disclose the lack of parallel execution. Never
claim that an independent review occurred when it did not.

## Hooks and completion

Review and trust the plugin hooks through `/hooks` before relying on them.
Installation does not grant hook trust. Measured hook semantics under Devin
(envelope capture: `knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md`):

- **Wire names are lowercase**: `exec`, `write`, `edit`, `ask_user_question`,
  `run_subagent`, `skill`. Claude-style matchers (`Bash`, `Write|Edit`, …)
  are dead — loaded but never dispatched.
- **Plugin `Stop` hooks fire** (empty matcher).
- **The bundled credential guard is bound**: plugin `hooks.json` binds
  `^(Bash|exec)$` (#8155), which also widened its in-body tool gate to admit
  `exec`; this change normalizes that gate onto the canonical
  `HOOK_TOOL_KIND` map. End-to-end coverage claim awaits the post-merge
  runtime trace.
- **SessionStart source matchers are dead** — `startup`, `resume`, `clear`,
  `compact` never fire; only the empty matcher `""` does.
- **`devin-session-start.sh` is bound in `hooks.json` (`""`), not `.devin`** —
  only plugin dispatch exports `CLAUDE_PLUGIN_ROOT`, which its proof-of-local
  sentinel and `cloud-detect.sh`'s `local` classification require. A `.devin`
  binding would write `hook_source:"repo"` and classify every local session
  `not-local:non-plugin-source`.
- **Project hooks need Devin-side registration**: this repository binds its
  hook set in `.devin/config.json` with anchored matchers; the authoritative
  per-hook dispositions live in `.claude/hooks/devin-dispositions.tsv`.
- **`.claude` permissions are not imported** — `.devin/config.json`
  `permissions` uses `Exec(prefix)`/`Read(glob)`/`Write(glob)`/`Fetch(pattern)`;
  this repository ports its allow/deny rules there. The deny rules are measured
  live under `smart` mode (`exec git push` and `rm -rf` were rejected through a
  `permissionDecision:"deny"` chain, not the engine's own path check); whether
  `allow`/`deny` gate under permissive modes is unprobed. `Read()` patterns
  rooted at `~` are registered but tilde-expansion semantics are UNMEASURED;
  `Exec()` string-match semantics (exact vs prefix) are UNMEASURED.
- **The tool envelope omits `.cwd`** — hooks resolve the working directory via
  `DEVIN_PROJECT_DIR` → `CLAUDE_PROJECT_DIR` → `$PWD` (measured: hook processes
  run with PWD at the project root and both env vars exported).
- **Hook response contracts**: `permissionDecision:"deny"` blocks and
  `updatedInput` rewrites, both measured live. `"ask"` and `"defer"` are
  UNVERIFIED under Devin — envelope-capture §6 records them as registered but
  never driven; a hook emitting either may be ignored or misrouted. The
  `PermissionRequest` hook event itself is UNVERIFIED.

Compaction hooks do not fire here, and that is not one of the measurements
above. `compaction-state.sh` (`PreCompact` / `SessionStart:compact`, #8323) is
a Claude Code API with no Devin equivalent, and under Cloud Mode plugin hooks
do not execute at all. No post-compaction re-read directive and no
evidence-based fresh-session recommendation are delivered; the skill-prose
fallback applies, so the end-of-work resume prompt still fires and carries no
`/clear` nudge. Do not report the behaviour as present.

Keep long-running workflows bounded by their iteration and cost gates.
Soleur's subscription and model usage are separate charges; substitute
Devin's model pricing in harness-specific billing disclosures. Soleur disclaims
warranty for runtime cost.

For asynchronous CI and merge work, own the wait, report changes, resolve
`BEHIND`, and finish the prescribed postmerge checks before claiming success.
Arm the watch as a background `run_subagent` exit-coded loop (see **Polling /
watches** below) rather than burning foreground turns on `sleep`-and-poll
cycles.
If a required capability cannot be mapped, report the exact unsupported gate
and retain incomplete status instead of silently skipping it.

## Devin-specific considerations

- **Skill invocation**: Devin exposes Soleur skills as slash commands (`/soleur:<skill>`). The `/soleur:go`, `/soleur:sync`, and `/soleur:help` commands are also slash commands.
- **Agent spawning**: Devin uses `run_subagent` tool instead of Claude's `Task` tool. `subagent_explore` has NO exec/git tool — review-panel agents that must run `git diff` or execute test suites spawn as `subagent_general` with an explicit report-only contract (no worktree writes; scratch in `mktemp -d`), or they reconstruct diffs by file comparison at degraded fidelity (#8471).
- **Polling / watches**: Devin has no Monitor tool (measured absent — envelope-capture §7). `get_output` only *reads* a backgrounded shell; nothing wakes the agent on output. For wait-until-actionable watches — CI settling, a PR reaching merged/`BEHIND`/`DIRTY`, a check failure — spawn a background `run_subagent` running an exit-coded poll loop: one distinct exit code per actionable transition, observe-and-report only. The subagent-completion notification is the only wake primitive, so the loop must exit to report; mutations (`gh pr update-branch`, merge) stay with the parent in the foreground where they are visible and approvable.
- **Permissions**: Devin's permission system differs from Claude's; use permissive defaults initially
- **MCP servers**: Devin supports the same MCP server format as Claude, so existing servers should work without modification
- **Worktree commits**: the tool envelope omits `.cwd`, so a bare `git commit` inside `.worktrees/` is false-denied by `guardrails.sh` block-commit-on-main (it resolves `$PWD` = main checkout). Attach `git -C <worktree-abs-path>` to worktree commits until #8254 lands.
