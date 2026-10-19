# Measurement Record — feat-opencode-harness

Every OpenCode fact this feature will assert, measured against a live OpenCode V2 install rather
than read from a page. Prose that restates these numbers should cite this file by section anchor.

**Append-only.** Correct a reading by adding a new dated section that cites the old one; never edit
a recorded reading's body.

Scope note: this record measures the *harness surface* — detection, discovery, invocation, tools,
hooks. It does not decide the adapter shape, and it does not by itself satisfy ADR-245's re-entry
criterion (a `Harness` member **and** a generator). Those are the spec's job, downstream of these
readings.

---

## Environment

| Fact | Value |
|---|---|
| OpenCode version | **2.0.32** (`opencode --version`) |
| Install | mise (`~/.local/share/mise/installs/opencode/2.0.32`) |
| Config | `~/.config/opencode/opencode.json` (body: `$schema`, `theme`, `autoupdate: false`) |
| Running server | `127.0.0.1:49374`, password in `~/.local/state/opencode/*.json` |
| Host repo | `/data/git-repositories/jikig-ai/soleur` |
| Date | 2026-10-17 |
| Plugin package inspected | `@opencode-ai/plugin@1.19.3` (unpkg `dist/index.d.ts`, `dist/v2/effect/plugin.d.ts`) |

The prior vendor reference `knowledge-base/project/specs/external/opencode.md` is dated
**2026-01-21** and describes the V1 config surface (plural/singular `.opencode` subdirs,
`modes/`, `tools` deprecated). Where the two disagree, this record is the current one — it is a
measurement, the other is a cited page.

---

## 1.0 — Detection markers

**Run 2026-10-17. Verdict: four candidate markers measured, none shared with another harness.**

The detection question ADR-274 makes load-bearing: *is there a variable set inside an OpenCode
session that is both present and CLI-specific?* Read from inside the live session.

### Method

`env | grep -i open` inside the OpenCode session, confirmed with
`node -e 'console.log(Object.keys(process.env).filter(k => k.startsWith("OPENCODE")))'`.

### Readings

| Variable | Observed value | Shape |
|---|---|---|
| `OPENCODE` | `1` | constant flag |
| `OPENCODE_SESSION_ID` | `ses_eb832230dffenhEfi6NEWvyp6P` | per-session id, `ses_` prefix |
| `OPENCODE_TERMINAL` | `1` | constant flag |
| `AI_AGENT` | `opencode` | harness name as a string |

Absent in the same environment: `CLAUDECODE`, `GROK_*`, `CODEX_THREAD_ID`, `DEVIN*`, `CURSOR*`.
So an OpenCode first-check must be **ordered before** the existing ones (or is provably
disjoint by these names) — none of the current four markers is set.

### Caveats (stated, not resolved here)

- `AI_AGENT=opencode` is the weakest candidate: the name is generic and could plausibly be set
  by a non-OpenCode host or a shell profile. `OPENCODE=1` is the preferred marker.
- The reading shows the variable is *set*; it does not yet show it is *CLI-only*. ADR-274's bar is
  the stricter one — a marker that also matches a non-CLI process fails. Confirming that is a
  spec step (spawn a plain shell and a `--standalone` server, check both).

### 1.1 — CLI-specificity probe (the ADR-274 bar)

**Run 2026-10-18, same host, `opencode v2.0.32`. Verdict: PASS — and the marker is narrower than
"CLI-only": it is tool-spawn-only.**

§1.0's last caveat left this open. The probe tests every OpenCode process mode reachable on this
host, plus the two bracketing arms.

#### Method

Read `/proc/<pid>/environ` for each mode, launched under a scrubbed `env -i HOME PATH TERM …` so an
inherited value cannot confound the reading — the same trap the `Test Fixture Conventions` section of
`plugins/soleur/AGENTS.md` names for `git`. The clean-env arm and the tool-child arm bracket the
result on both sides.

#### Arms

| Arm | How launched | `OPENCODE` | `OPENCODE_SESSION_ID` | `OPENCODE_TERMINAL` | `AI_AGENT` |
|---|---|---|---|---|---|
| Clean env | `env -i /usr/bin/env` | absent | absent | absent | absent |
| Server | `env -i … opencode serve --port 4999` | absent | absent | absent | absent |
| ACP (editor embed) | `env -i … opencode acp` | absent | absent | absent | absent |
| Session runtime | the live `opencode.exe` process (208 vars) | absent | absent | absent | absent |
| Tool child | a shell the session spawned | `1` | `ses_…` | `1` | `opencode` |
| Headless `run` | `opencode run --auto …`, read via its own tool child | `1` | `ses_eb3b2ae7…` | `1` | `opencode` |

#### Verdict

The marker is set **only** in the environment OpenCode constructs for a process it spawns as a tool
call. It is absent from a clean environment, from `serve`, from `acp` — and, the load-bearing one,
from the session runtime process *itself*, whose 208-variable environment was read directly. So it
identifies exactly "a process an OpenCode agent session is driving", which is the set Soleur code
runs inside.

Headless `run` is covered by the same property, via its own tool child. That arm cannot use the
`env -i` scrub — it was launched from an interactive tool shell that already carried `OPENCODE=1`,
so mere presence would be confounded by inheritance. The `ses_` id is what resolves it: the file
shows `ses_eb3b2ae7…`, not the launching session's `ses_eb832230…`. The headless session therefore
**overwrote** the inherited values rather than passing them through — injection, not inheritance.

This clears ADR-274's bar in the stricter direction: the marker matches no non-session OpenCode
process. Consequences:

- Task 1.2.2 proceeds — the `detectHarness` predicate is on `OPENCODE`.
- The predicate stays `OPENCODE`-only. §1.0's caveat on `AI_AGENT` holds, so it is not used as a
  primary test even though it is present in the same arm.

#### Ordering

`OPENCODE` is checked **after `CLAUDECODE`, before `GROK_*` / `CODEX_THREAD_ID` / `DEVIN*`**.
`CLAUDECODE` keeps its established first position (the existing precedence tests pin it).
`GROK_HOME` / `DEVIN_HOME` are installation *paths* that a shell profile can export into any
session — including an OpenCode one — so they must not be able to shadow a marker OpenCode injects
itself. Running Claude inside OpenCode is an accepted, unmeasured edge; §1.0 already recorded that
no other marker is present in a plain OpenCode session.

#### Refuted reading (recorded so it is not reintroduced)

The first ACP arm located the process with `pgrep -f 'opencode acp'` and read a full marker set
apparently under `env -i`. That process was the **wrapper subshell** (`sh -c … opencode acp`), whose
environment is the outer session's, not the ACP process's. Re-run against the exec'd process
(backgrounded `$!`, `comm=opencode`), every marker is absent. The wrapper is not the subject.

---

## 2.0 — Skill discovery

**Run 2026-10-17. Verdict: the canonical Soleur skill tree is consumable directly; discovery
roots are Claude-Code-compatible; project-local roots need a git worktree; symlinked skill dirs
are NOT followed.**

### 2.1 Roots (from `https://opencode.ai/docs/skills/`)

```
Project config            .opencode/skills/<name>/SKILL.md
Global config             ~/.config/opencode/skills/<name>/SKILL.md
Project Claude-compatible .claude/skills/<name>/SKILL.md
Global Claude-compatible  ~/.claude/skills/<name>/SKILL.md
Project agent-compatible  .agents/skills/<name>/SKILL.md
Global agent-compatible   ~/.agents/skills/<name>/SKILL.md
```

Plus the config key `skills` — an array of local dirs or HTTP catalog URLs. Project-local paths
are resolved by walking up from cwd to the git worktree.

### 2.2 Readings

| Probe | Result |
|---|---|
| Symlinked `<root>/plan` under `.opencode/skills`, `.claude/skills`, `.agents/skills`, no config | **0 skills** — symlinked dirs not followed |
| Real copy of `plan`/`work` under project `.opencode/skills`, no git repo | **0 skills** |
| Same, after `git init` in the project | **2 skills** (`plan`, `work`) — project-local discovery needs a git worktree |
| Canonical `plugins/soleur/skills` via `skills` config key | **103 skills** registered, all `path` = canonical repo path |

### 2.3 Naming and flag semantics

| Property | Measured |
|---|---|
| Skill id | **bare directory basename** — `plan`, never `soleur:plan`. No namespace prefix. |
| Soleur name conformance | All match OpenCode's rule `^[a-z0-9]+(-[a-z0-9]+)*$`, 1–64 chars, name == dir name |
| `disable-model-invocation: true` (Claude convention) | **Honored** — 8 of the 9 flagged skills registered with `autoinvoke: false`; the 9th mentions the flag in body prose only, not frontmatter |
| OpenCode-native equivalent | `metadata.opencode/autoinvoke: "false"` (frontmatter string) |

### 2.4 Consequence for the adapter

Canonical skill references in Soleur prose are `soleur:<name>`, but the OpenCode skill id is the
**bare basename**. The two do not match, so a skill reference written for Claude/Grok/Devin is not
automatically resolvable by OpenCode — this is the first real gap (see §10).

Collision note: the flat Soleur names (`plan`, `work`, `review`, `go`, `sync`, `help`, `version`)
are NOT namespaced, unlike on Claude Code, so they can collide with a user's own OpenCode skills.
No collision was observed in the measured environment (120 skills total, no duplicate names).

---

## 3.0 — Agent discovery

**Run 2026-10-17. Verdict: agents register from `.opencode/agents/**/*.md`, but land as
`mode: primary` and are therefore NOT spawnable; a `mode: subagent` generator step is required.
`name:` frontmatter is ignored (path-derived ids).**

### Method

Copied canonical `plugins/soleur/agents/{engineering,product}` (36 files) into a scratch project's
`.opencode/agents/`, then read `GET /api/agent`.

### Readings

| Probe | Result |
|---|---|
| Symlinked `agents/engineering` + `agents/product` dirs | **0 custom agents** — symlinks not followed |
| Real copies (36 files) | **35 custom agents** registered |
| `mode` for every Soleur agent | **`primary`** — Claude-Code agents carry no `mode:` field, so all defaulted to primary |
| One copy with `mode: subagent` injected | registered as **`subagent`** — the field is the gate |
| Agent id | **path-derived with `/`** — `engineering/cto`, `engineering/review/security-sentinel` |
| Agent `name` | equals the path (`engineering/cto`), **not** the frontmatter `name: cto` — frontmatter `name` ignored |
| `model: inherit` (all Soleur agents) | accepted, resolved to **`null`** (inherits session model) |
| `description` | honored |

### Consequence

Two generator obligations, both measured rather than assumed:

1. **`mode: subagent`** must be added to every agent the harness is to spawn. Without it the
   agent is a primary agent and the Task tool cannot reach it.
2. **id mapping**: canonical `soleur:engineering:cto` → path-derived `engineering/cto`. The
   `name:` frontmatter field is not a usable identity on this harness (it is ignored).

---

## 4.0 — Commands

**Run 2026-10-17. Verdict: all four canonical commands discovered from `.opencode/commands/`.**

`commands/*.md` discovered from `.opencode/commands/`: `go`, `help`, `sync`, `version` (the four
tracked Soleur commands). The API's `id` field is null; the name is the filename stem. Commands use
`$ARGUMENTS` (docs) and accept `agent` / `model` / `subagent` frontmatter.

---

## 5.0 — Tool surface

**Sources: `https://opencode.ai/docs/tools/` and the permission-key table in
`https://opencode.ai/docs/agents/`.**

### 5.1 Built-in tools (docs, complete list)

`bash`, `edit`, `write`, `read`, `grep`, `glob`, `apply_patch`, `skill`, `webfetch`, `websearch`,
`question`, `lsp` (experimental). Custom tools and MCP tools extend this set.

### 5.2 Permission keys name the operator-visible tools

`read`, `edit` (gates `write`/`edit`/`apply_patch`), `glob`, `grep`, `list`, `bash`, `task`,
`external_directory`, `webfetch`, `websearch`, `lsp`, `skill`, `question`, `doom_loop`.

### 5.3 Subagents are invoked via a **Task** tool

Docs (agents page): subagents "are invoked by primary agents via the **Task** tool"; `@`-mention to
invoke manually; `permission.task` (glob patterns) gates which subagents an agent may invoke;
`hidden: true` hides a subagent from autocomplete but it "can still be invoked by the model via the
Task tool".

### 5.4 Absences (checked, not assumed)

| Claude tool | OpenCode V2 | Evidence |
|---|---|---|
| `TodoWrite`/`Task*` todo surface | **Absent** | no `todo` token in the tools page, agents page, skills page, plugins page, rules/permissions/commands pages |
| `Monitor` / `AwaitShell` | **Absent** | no `Monitor`/`AwaitShell` token in the same pages |
| `Cron*` / `PushNotification` / `RemoteTrigger` / `ScheduleWakeup` | **Absent** | same |

---

## 6.0 — Plugin / hook API

**Source: `@opencode-ai/plugin@1.19.3` type definitions (authoritative), cross-checked against
`https://opencode.ai/docs/plugins/`.**

### 6.1 Loading

`.opencode/plugins/*.ts` (project), `~/.config/opencode/plugins/*` (global), and the `plugin`
config array (npm package names, scoped or unscoped). Load order: global config → project config →
global plugin dir → project plugin dir.

### 6.2 Hook keys (`Hooks` interface, `dist/index.d.ts`)

`dispose`, `event`, `config`, `tool` (custom `ToolDefinition` map), `auth`, `provider`,
`chat.message`, `chat.params`, `chat.headers`, `permission.ask`, `command.execute.before`,
`tool.execute.before`, `shell.env`, `tool.execute.after`,
`experimental.chat.messages.transform`, `experimental.chat.system.transform`,
`experimental.provider.small_model`, `experimental.session.compacting`,
`experimental.compaction.autocontinue`, `experimental.text.complete`, `tool.definition`.

### 6.3 Event catalog (`event` hook; docs plugins page)

`command.executed`; `file.edited`, `file.watcher.updated`; `installation.updated`;
`lsp.client.diagnostics`, `lsp.updated`; `message.part.removed/updated`, `message.removed/updated`;
`permission.asked/replied`; `server.connected`; `session.created/compacted/deleted/diff/error/idle/status/updated`;
`shell.env`; `tool.execute.before/after`; `tui.prompt.append`, `tui.command.execute`, `tui.toast.show`.

### 6.4 Stop-equivalent

There is **no dedicated Stop hook**. `session.idle` is the event a plugin subscribes to for
"session went quiet"; the docs' notification example fires on `session.idle`. Whether that is
sufficient for Soleur's `<promise>DONE</promise>` completion contract is a spec question, not
settled by this reading.

### 6.5 Note on the V2 plugin API shape

The npm package also exposes an **Effect-based** plugin interface at
`@opencode-ai/plugin/v2/effect` (`Plugin = { id, effect: (context) => Effect<void> }`,
`define()`), distinct from the classic `(input) => Promise<Hooks>` form the docs page shows. A
plugin may be written to either; the spec should pick one deliberately rather than assume the
docs' shape is the only one.

### 6.6 — Correction pass, 2026-10-19: the V2 plugin contract (§6.2–§6.5 read the V1 package)

**Run 2026-10-19, OpenCode 2.0.32. Verdict: the runtime implements the V2 plugin contract, and it
rejects the V1 module shape §6.2/§6.5 describe. This also closes the §10 open item "the plugin
contract has not been exercised" and settles spec D3 / task 3.2.2.**

Correction by citation, per the append-only rule; the bodies above stay as recorded.

Sources: the installed CLI, measured live; `https://opencode.ai/v2/docs/build/plugins`;
`https://opencode.ai/v2/docs/api`; the npm registry. Method: hermetic `HOME` with
`XDG_*` inside it (identical to §11.6), a git-committed scratch project as cwd, an explicitly
started server, `OPENCODE_PASSWORD` from the `server password <pw>` line, and a probe plugin that
appends to a log file. Three arms differ **only** in the plugin module's export shape; the
directory (`<configdir>/plugins/`) and the config key (`"plugins"`) are identical.

| Arm | Module shape | Result |
|---|---|---|
| A | `export const Foo = async () => ({ … })` — the V1 named export the V1 docs page shows (§6.2/§6.5) | **Rejected.** Server log: `msg="failed to load plugin" … cause="PluginModule.LoadError: Plugin must export a default definition with an id and an effect or setup function. (cause: SchemaError(Missing key at ["default"]))"` |
| B | `export default { id, async setup(ctx) { … } }` — V2 | **Loaded and ran.** The plugin's own first log line (`SETUP_OK`) is present |
| C | Arm B's module, with **no** `"plugins"` entry in `opencode.json` | **Loaded and ran** from the global discovery directory |

Readings:

- The config key is `plugins` (plural), and a relative entry resolves against the config file that
  contains it. The load is logged as `msg="loading plugin" id=<abs> entrypoint=file://<abs>`.
- The global discovery directory `<configdir>/plugins/*.js` loads **without** any `plugins` entry
  (arm C logged the load line and the plugin's setup ran). Both delivery routes therefore work.
- `ctx`'s keys, read from inside `setup` (measured, not from docs):
  `app, location, options, agent, aisdk, command, credential, event, experimental, generate, model,
  provider, integration, mcp, permission, plugin, reference, rpc, skill, storage, tool, vcs,
  websearch, worktree, session, shell`.
- V2 hook surface (build docs, "Hooks"; consistent with `ctx` above):
  `ctx.session.hook(name, cb, opts?)` with `name` one of
  `prompt | context | compaction | generate | title | model.request | http.request | http.response |
  experimental.ws.handshake | experimental.ws.send | experimental.ws.receive | retry`;
  plus `ctx.permission.hook("evaluate")`, `ctx.shell.hook("create.before")`, and
  `ctx.tool.hook("execute.before" | "execute.after")`. Every one of these is handed a **mutable
  event object** and communicates only by mutating it; none returns a decision about stopping.
  A plugin may not redirect prompt admission (`Session and message IDs are readonly; a hook cannot
  redirect admission`) and the prompt hook `do[es] not expose a typed rejection API`.
- `ctx.event.subscribe(options?) -> AsyncIterable<OpenCodeEvent>` is the event surface. A live
  capture while `POST /api/session` and `POST /api/session/{id}/prompt` were issued yielded
  `integration.updated, model.updated, provider.updated, vcs.branch.updated, agent.updated,
  command.updated, skill.updated, websearch.updated, reference.updated, plugin.updated,
  session.inbox.enqueued, session.execution.started, session.instructions.updated,
  session.inbox.delivered`.
- `POST /api/session/{id}/prompt` takes `{"text": …}`; the v1-style `{"parts":[…]}` body is rejected
  with `InvalidRequestError: Missing key at ["text"]`. The v1 path `/api/session/{id}/message` is
  `GET`-only (a `POST` answers 404).
- "Idle" in V2 is a **persisted message type** — `Session.Message.Idle`, a member of the
  `Session.Message.Info` union — not a hook and not a controllable boundary.

Verdict (closes Phase 0.2): **there is no blocking Stop contract.** No hook can defer a stop, force
a continuation, or veto a completion, and the event surface is a one-way iterator with no return
channel. "Session went quiet" is therefore *observation only*: a plugin can notice it and cannot act
on it. The advisory `<promise>DONE</promise>` marker plus structural verification is the correct and
only available design (spec D3). Task 3.2.2 is capped accordingly — the hook module may **not** claim
a block; it records the advisory marker's state and nothing more.

Package identity (npm registry, 2026-10-19), which corrects §6.0 and the spec's task 3.2.4:

| Package | Latest | What it is |
|---|---|---|
| `@opencode/plugin` | `2.0.32` | **V2** authoring interfaces + loader — "Authoring interfaces and runtime loader support for OpenCode V2 plugins". Version-matched to the CLI |
| `@opencode-ai/plugin` | `1.19.3` | **V1** — the package §6.2 read `dist/index.d.ts` from, and the one task 3.2.4 proposed to pin |

So the pin is `@opencode/plugin` (2.0.32), **not** `@opencode-ai/plugin`: pinning the latter against a
V2 CLI pins exactly the API the runtime rejects (arm A). The "CLI-vs-package version skew" the spec
recorded (CLI 2.0.32 / package 1.19.3) is not a skew — it is a package rename between API
generations, and §6.5's `/v2/effect` subpath is the same V1 package's Effect entry, not the V2
surface.

Caveat (stated, not resolved): no turn was driven to completion — a hermetic environment has no
provider credential — so the `session.idle` **event** is inferred from the V1 catalog and was not
observed here. The verdict does not depend on it: the hook surface is enumerated in full, and no
member of it can defer a stop.

---

## 7.0 — Instructions / rules

From `https://opencode.ai/docs/rules/`:

- `AGENTS.md` in the project (and a global one) is the instructions file.
- **Claude Code fallbacks**: `CLAUDE.md` in the project (used only if no `AGENTS.md` exists) and
  `~/.claude/CLAUDE.md` (used only if no `~/.config/opencode/AGENTS.md`).
- The `instructions` config key adds external paths or URLs.

Soleur's root `AGENTS.md` index + `AGENTS.rules.md` corpus therefore has a native home; the
index/body split is unaffected.

---

## 8.0 — Permissions, policies, models, headless

- **Permissions**: an ordered ruleset (`permissions` config; per-agent override) with actions
  `allow` / `ask` / `deny`; glob/pattern form for `read`, `edit`, `glob`, `grep`, `list`, `bash`,
  `task`, `external_directory`, `lsp`, `skill`.
- **Policies**: a separate hard-deny list — actions `provider.use`, `tool.use`, `integration.use`
  with `allow` / `deny`.
- **Models**: `provider/model#variant` (e.g. `opencode/big-pickle`). Confirmed by
  `opencode run --model` help text.
- **Headless**: `opencode run [flags] <message>` with `--model provider/model#variant`,
  `--agent <name>`, `--format default|json`, `--session`, `--continue`, `--fork`, `--auto`.

---

## 9.0 — Discovery-proof candidate (for the CI gate ADR-245 requires)

**Run 2026-10-17. Verdict: a listing exists and is scriptable, but is NOT hermetic as-is.**

OpenCode exposes `GET /api/skill` (`operationId: skill.list`) returning
`{ location, data: Skill.Info[] }` where `Skill.Info` = `{ id, name, description?, autoinvoke?, path, content }`.

```
opencode api skill.list          # works from a project dir
```

Measured: from `/tmp/opencode/probe-project` (a git repo with a `skills` config pointing at the
canonical tree) it returned the 103 Soleur skills plus **17 global/other skills** loaded from
`~/.claude/skills/**` and `~/.agents/skills/**` — 120 total, no duplicate names.

Consequence: unlike `codex debug prompt-input` / `devin skills list`, the probe's result is
polluted by the operator's global skill roots. A CI arm must control `HOME` **and** the project
dir (the `harness-discovery-smoke.ts` pattern already does this for Codex/Devin), and must key on
`path` rather than on `name` to tell a Soleur registration from a global one. `id` is bare
(`plan`), so the Codex/Devin parsers' `soleur:`-prefixed regexes do not port.

---

## 10.0 — Open gaps this record does not close

Each is a spec/decision item, not a measurement defect.

1. **Namespacing.** OpenCode skill ids are bare basenames; Soleur canonical refs are `soleur:<name>`.
   Either references get rewritten per-harness (generator), or Soleur accepts a bare-name collision
   surface on this harness. ADR-226's census treats `soleur:<x>` as canonical, so this is a
   BOUNDARY/parity question, not a cosmetic one.
2. **Agent `mode: subagent`** must be generated; canonical agents have no `mode:` field.
3. **Agent id mapping** `soleur:a:b:c` → `a/b/c`, with `name:` frontmatter ignored.
4. **Detection CLI-specificity.** §1 measures the variables are set; proving `OPENCODE` is not set
   by a non-CLI process (ADR-274's bar) is outstanding.
5. **Completion / Stop.** No Stop hook; `session.idle` is the candidate. Soleur's
   `<promise>DONE</promise>` contract needs an explicit mapping or a documented refusal.
6. **Todo surface.** No todo tool. Skills that carry "TodoWrite" instructions need a per-harness
   mapping (as Codex does: "use the available plan tool, or file-based task tracking").
7. **Generator scope (ADR-245).** Measured: skills register **directly** from the canonical tree
   via `skills` config — no skill tree needs generating. Agents and commands DO need a generated
   `.opencode/` tree (mode, id shape). So the generator's scope is narrower than Cursor's, and the
   decision of what it emits (config file vs. generated dir) is open.
8. **Distribution.** OpenCode plugins load from `.opencode/plugins/` or npm/config; Soleur's
   delivery path is a Claude Code manifest + marketplace. The OpenCode install story is unmeasured.

---

## 11.0 — Correction pass, 2026-10-18 (re-measures §2.2, §3.0, §9.0)

**Run 2026-10-18, OpenCode 2.0.32 (unchanged). Verdict: three recorded readings reproduce, one is
refuted, and two load-bearing behaviors were missed — the listing is empty until a session exists,
and `model: inherit` silently drops an agent.**

Correction by citation, per the append-only rule; the bodies above stay as recorded.

### Method (differs from §2.2/§3.0 in two ways)

1. A hermetic `HOME` (`mktemp -d`) with `XDG_CONFIG_HOME`/`XDG_DATA_HOME`/`XDG_STATE_HOME` inside it,
   a git-committed scratch project as cwd, and an **explicitly started** server
   (`opencode serve --port N`) instead of the shared background daemon. Auth is the
   `OPENCODE_PASSWORD` line the server prints on stdout; without it every `/api/*` route answers
   `UnauthorizedError`. (`opencode api` also reads `GET /api/info` first — a bare `curl` skips that.)
2. `opencode api --standalone` works and is self-cleaning, but spawns a fresh server per call. The
   explicit server is what permits a sequence of reads against one process.

### 11.1 — The listing is empty until a session exists (§2.2/§3.0/§9.0 all read it mid-session)

One hermetic server, config already in place:

| Read | `GET /api/skill` | `GET /api/agent` |
|---|---|---|
| after boot (10–12 s settle) | **0** | **7** (built-ins only) |
| after `POST /api/session` | **105** | **74** |

Rewriting the config file (config-directory watch) or calling `POST /api/location/reload` also
clears it without a session. So a pre-trigger read is not evidence of a broken install — it is
evidence the location has no session yet. Every zero this pass first observed was a pre-trigger read.

### 11.2 — `model: inherit` drops the agent (refutes the §3.0 `model: inherit` row)

Four agents in one hermetic `<configdir>/agents/`, each with a `description`, read after a session:

| Frontmatter | Registered |
|---|---|
| `description` only | **yes** (`mode: primary`) |
| `+ mode: subagent` | **yes** (`mode: subagent`, no `model` key — inherits) |
| `+ model: inherit` | **NO — dropped entirely** |
| `+ model: anthropic/claude-sonnet-4-5` | **yes** (`model: {id, providerID}`) |

§3.0's "`model: inherit` … accepted, resolved to `null`" is **refuted**. `inherit` is not an OpenCode
model ref, so the file yields no document and the agent never appears. The generator must **omit**
`model:`; omitting it is this harness's spelling of "inherits the session model". The first draft of
`sync-opencode-adapter.ts` emitted `model: inherit` on all 67 stubs and `GET /api/agent` showed only
the 7 built-ins.

### 11.3 — Project-local roots did not register (cites §2.2 rows 2–3)

Real copies of `plan`/`work` under a `git init`-ed project's `.opencode/skills`, and `work`/`review`
under its `.claude/skills` and `.agents/skills`, read **after** `POST /api/session`, returned **0**.
The `skills` config key pointing at the canonical tree returned **103** in the same setup. The root
the adapter can rely on is therefore the config `skills` key. Whether the project-local rows need a
trust/registration step this probe did not perform is **not settled here**.

### 11.4 — Full-surface discovery proof (supersedes §9.0's "not hermetic" caveat)

Hermetic `HOME`, adapter installed with `scripts/install-opencode-adapter.ts`, one session created:

| Surface | Total | Soleur | Other |
|---|---|---|---|
| `GET /api/skill` | **105** | **103** — every `path` under `<checkout>/skills/` | 2 built-ins (`/builtin/opencode.md`, `/builtin/report.md`) |
| `GET /api/agent` | **74** | **67** stubs (`engineering/cto`, …) | 7 built-ins |
| `GET /api/command` | **6** | **4** (`go`, `help`, `sync`, `version`) | 2 built-ins (`init`, `review`) |

`HOME` control alone makes this hermetic: with `HOME` redirected, `~/.claude/skills` and
`~/.agents/skills` are not read, so the 17 "global/other" skills §9.0 saw do not appear. Keying on
`path` is still the discriminator, and is what the 103-of-105 split above uses.

### 11.5 — Probe recipe

```bash
HOME=<scratch> XDG_CONFIG_HOME=<scratch>/.config XDG_DATA_HOME=<scratch>/.local/share \
  XDG_STATE_HOME=<scratch>/.local/state  opencode serve --port N   # cwd = a git-committed project
# take <pw> from the `server password <pw>` line on stdout
OPENCODE_PASSWORD=<pw> opencode api --server http://127.0.0.1:N POST /api/session -d '{}'
OPENCODE_PASSWORD=<pw> opencode api --server http://127.0.0.1:N GET /api/skill > out.json
```

Two footguns: `GET /api/skill` returns each skill's full `content` (~3 MB for 103) — read it from a
**file**, a pipe truncates near 139 kB; and with `HOME` redirected the `opencode` shim re-resolves
through mise and **installs another copy into the scratch HOME** (hit `Disk quota exceeded` once) —
invoke the resolved binary path directly to avoid it.

### 11.6 — The discovery arm's probe recipe, corrected by building it

Readings taken while implementing the `opencode` arm of `scripts/harness-discovery-smoke.ts`
(OpenCode 2.0.32, hermetic `HOME` + `XDG_*`, adapter installed with
`scripts/install-opencode-adapter.ts --target <home>/.config/opencode`).

**The listing is built ASYNCHRONOUSLY, and §11.1's "needs a session" was a timing artifact.**
Polling `GET /api/skill` every 1–2 s from boot with no session and no reload:

| Elapsed | `data` length |
|---|---|
| t=0 s | 0 |
| t=3 s | **105** |

The scan appears to start on the first request rather than at boot — a first read at t=8 s also
returned `0`, then `2`, then the full set. Either way the reading is only meaningful once polled to
settlement, and `POST /api/session` is **not** part of the recipe. §11.1's attribution to the session
is superseded: it was the second request, not the session call, that observed the populated list.

**`POST /api/location/reload` CLEARS the listing before rebuilding it.** Issued on a settled server:
`data` drops to **2** (built-ins only) and returns to **105** about 3 s later. So it must not be part
of the probe — a reload immediately before the read makes the arm race its own reset.

**The payload MUST be read from a file. `execFileSync` truncates a large stdout and reports
SUCCESS.** Same settled payload, same call, two consumers:

| Consumer | Bytes | `JSON.parse` |
|---|---|---|
| shell redirect `> out.json` (and `\| wc -c`) | 3,069,018 | valid |
| `spawnSync` with an `fd` opened on `out.json` | 3,069,017 | valid |
| bun `execFileSync(..., { maxBuffer: 32*1024*1024 })` | 803,968 (also 945,818 chars on another run) | **INVALID** — string cut mid-`content` |

`maxBuffer` is not honoured on this path: the truncation point differed between runs, the call
returned without throwing, and the unclosed string made a correct install grade `unparseable-output`
(exit 3). §11.5's "a pipe truncates near 139 kB" is corrected: the reproduced truncation is bun's
`execFileSync` at ~0.8–0.9 MB, not a 139 kB shell pipe — that figure came from `| head`, which closes
the pipe early and is not the failure mode here.

**Hermetic `HOME` is only safe with the absolute binary.** With `HOME` redirected, the `opencode` on
`PATH` (`~/.local/bin/opencode`, a version-manager shim) resolves its install THROUGH `HOME`,
reinstalls into the scratch dir and hangs (`env -i PATH=$PATH opencode --version` exceeded 180 s);
`readlink -f` follows the chain to
`.../mise/installs/opencode/2.0.32/node_modules/.bin/opencode`, which needs no `HOME` and answers
`opencode v2.0.32` under `env -i`. With that binary, `HOME` + `XDG_*` can all be hermetic, which
reproduces §11.4 exactly: **105** skills, **103** with a `path` under `<checkout>/skills/`, the
outside set being exactly `/builtin/opencode.md` and `/builtin/report.md`.

**End-to-end, the arm passes.** `bun scripts/harness-discovery-smoke.ts --harness opencode` →
`harness-discovery[opencode]: exit=0 reason=ok (mode=single)` in **~5 s**, `missing: []`,
`extra: []`, `badMultiplicity: []`. `mode=single` is a new verdict mode for an expectation with no
cross-root (k≥2) name — the OpenCode shape, where reporting `indeterminate` would read as a defect.
