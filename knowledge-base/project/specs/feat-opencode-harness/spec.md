---
title: OpenCode harness adapter
status: specified
date: 2026-10-17
branch: feat-opencode-harness
lane: single-domain
brand_survival_threshold: single-user incident
measurements: knowledge-base/project/specs/feat-opencode-harness/measurements.md
---

# Feature: OpenCode harness adapter

## Problem Statement

Soleur ships one plugin tree to four supported harnesses — Claude Code, Grok Build, Codex, Devin
— plus an unsupported Cursor slice 1. An operator running OpenCode V2 today gets none of it: the
session is `unknown`, and the `unknown` routing contract names the Skill tool and the Task tool in
Claude's vocabulary.

OpenCode is a better-fit host than Cursor was. It has native skills, agents, commands, MCP, a
plugin/hook API, and — measured — it consumes Soleur's **canonical** skill tree directly, so the
per-harness tree that ADR-245's generator obligation exists for is needed for agents and commands
only, not skills. The measurements this spec rests on live in
`knowledge-base/project/specs/feat-opencode-harness/measurements.md`; sections below cite it by
anchor and this spec does not restate its numbers.

## Goals

- An operator who already runs Soleur in Claude Code, Grok Build, Codex, or Devin can run the same
  lifecycle in OpenCode V2.
- The harness meets ADR-245's re-entry criterion: a `Harness` union member with the adapter
  functions it implies, **and** a generator for the per-harness tree. Never a hand-maintained copy.
- Detection is a measured marker, per ADR-274, not a guess.
- Canonical skills, agents, and commands stay the source of truth; OpenCode-specific shapes are
  generated.

## Non-Goals

- **No claim of support before the measures exist.** Following the Cursor slice-1 precedent
  (ADR-274), the public harness list, README, comparison pages, and legal copy stay unchanged until
  the Acceptance Criteria below are met; the flip is a separate, CLO-reviewed change.
- **No per-harness skill tree.** Measurement §2.2 shows canonical skills register from the config
  `skills` key with no copy. Generating one would create the drift surface ADR-245 deleted.
- **No marketplace submission.** Install is from this repo; a gallery listing is a separate
  contract nothing here authorizes.
- **No hand port.** If a per-harness artifact is needed, a generator produces it (measurement §10.0
  item 7 fixes its scope).

## Functional Requirements

### FR1: Harness detection

`detectHarness` returns `opencode` for a live OpenCode session, ordered so it cannot be shadowed by
another harness. Marker: `OPENCODE` (measurement §1.0), with `OPENCODE_SESSION_ID` /
`OPENCODE_TERMINAL` as corroboration and `AI_AGENT=opencode` explicitly **not** used as the primary
predicate (generic name, measurement §1.0 caveat). The predicate must be proven CLI-specific before
it ships (see Unmeasured steps).

### FR2: Operator entry points and skill routing

- Skills are dispatched by bare id (measurement §2.3), e.g. `plan`, not `soleur:plan`.
- `formatSkillInvocation` gains an `opencode` arm returning the bare name; canonical docs keep the
  `soleur:<name>` form (ADR-226 census unchanged).
- The generated `opencode/INSTRUCTIONS.md` states, in the harness's own terms, how to load a
  Soleur skill and where the canonical `SKILL.md` lives when a bare id is ambiguous.

### FR3: Agent spawning

- Agents are spawned via OpenCode's **Task** tool (measurement §5.3).
- Every generated agent carries `mode: subagent` (measurement §3.0) — without it the agent is a
  primary agent the Task tool cannot reach.
- Agent identity is the path-derived id (`engineering/cto`), not the registry id
  (`soleur:engineering:cto`) and not the frontmatter `name:` (ignored, measurement §3.0). The
  adapter renders the path id at spawn.

### FR4: Commands

The four tracked commands (`go`, `help`, `sync`, `version`) are discoverable from OpenCode's
commands directory (measurement §4.0). `$ARGUMENTS` is the argument placeholder.

### FR5: Guards and hooks

The credential guard, destructive-command guard, session-start behaviour, and compaction re-read
directive are delivered through an OpenCode **plugin** (measurement §6.6) written against the V2
contract — `export default { id, setup(ctx) }` — not a `hooks.json`. The guard surface is
`ctx.tool.hook("execute.before")` and `ctx.shell.hook("create.before")`; session-start rule injection
is `ctx.session.hook("context")`; the compaction re-read is `ctx.session.hook("compaction")` plus
`context`. There is **no** Stop hook — `session.idle` is an observation, not a boundary. D3 and D4
below state what is and is not preserved.

### FR6: Repository instructions

Soleur's root `AGENTS.md` index plus the `AGENTS.rules.md` corpus load natively (measurement §7.0);
no rename, no copy. The generated `opencode/INSTRUCTIONS.md` is the adapter's tool/path mapping
document, the OpenCode peer of `codex/INSTRUCTIONS.md`.

### FR7: Discovery proof in CI

A non-required `harness-discovery` arm proves OpenCode **registers** the skills the install
declares, using the `skill.list` surface (measurement §9.0). Because that listing is polluted by
the operator's global skill roots, the arm controls `HOME` and the project dir and keys on `path`,
not `name`. It inherits ADR-245's exit taxonomy (3 = unresolved/unreadable, 1 = measured loss).

### FR8: Permissions and model tiers

Soleur's allow/deny posture is expressed in OpenCode's `permissions` ruleset; hard denies use
`policies` (measurement §8.0). Semantic model tiers resolve through `harness-model-map` to
`provider/model#variant` (measurement §8.0).

## Technical Requirements

### TR1: `Harness` union + adapter arms

Add `"opencode"` to the `Harness` union in `plugins/soleur/lib/harness.ts`, plus the
`formatSkillInvocation` / `formatAgentSpawn` / routing-instruction arms the union implies.
`workflow-fidelity.ts` gains an `opencode` arm where the invocation form differs.

### TR2: Generator (ADR-245 obligation)

A generator script, `plugins/soleur/scripts/sync-opencode-*.ts`, modelled on
`sync-grok-agent-compat.ts` and `sync-cursor-name-map.ts`, with a `--check` mode that exits
non-zero on drift. Its scope is set by measurement §10.0 item 7:

| Artifact | Generated? | Why |
|---|---|---|
| Skills | **No** | canonical tree registers via config (measurement §2.2) |
| Agents `plugins/soleur/opencode/agents/**/*.md` | **Yes** | `mode: subagent` + path id + description (measurement §3.0) |
| Commands `plugins/soleur/opencode/commands/*.md` | **Yes** | OpenCode reads its own commands dir (measurement §4.0) |
| `plugins/soleur/opencode/INSTRUCTIONS.md` | **Yes** | tool/path mapping doc (FR6) |
| Hook plugin (`plugins/soleur/opencode/*.ts`) | **Source, not generated** | adapter logic, like `harness.ts` itself |

### TR3: Tool-translation table

`plugins/soleur/opencode/INSTRUCTIONS.md` carries a `## Tools` table covering the closed
`CLAUDE_CODE_TOOLS` vocabulary (measurement §5.0 for the OpenCode side). Rows with no OpenCode
equivalent are stated as unsupported — the record shows no `todo`, `Monitor`/`AwaitShell`, or
`Cron*`/`PushNotification`/`RemoteTrigger` (measurement §5.4).

### TR4: Model tier map

`harness-model-map.ts` gains an `opencode` entry mapping `cheap` / `standard` / `strong` /
`advisor` to OpenCode `provider/model#variant` slugs. Slug choices follow ADR-110's
bump-one-table rule; `inherit` stays a passthrough — it is a source-form value, not a semantic
tier, and it is never written into a generated agent stub (measurement §11.2).

### TR5: Per-harness hook registry (ADR-223)

The OpenCode hook set is its own registry — an OpenCode plugin module — with a disposition row per
hook, mirroring `.claude/hooks/devin-dispositions.tsv`'s shape. Event-to-hook mapping against the V2
surface (measurement §6.6): `PreToolUse(Bash)` → `ctx.tool.hook("execute.before")` (plus
`ctx.shell.hook("create.before")` on the shell path); `SessionStart` → plugin `setup` plus
`ctx.session.hook("context")` for rule injection; `PreCompact` → `ctx.session.hook("compaction")`;
`Stop` → **no equivalent** — the row is `observation-only (session.idle)`, never a block. The module
must be `export default { id, setup(ctx) }`; the V1 named-export form is rejected by the runtime
(measurement §6.6 arm A).

### TR6: Discovery-smoke parser + CI job

`plugins/soleur/scripts/harness-discovery-smoke.ts` gains an `opencode` arm: extend the `Harness`
type and `parseArgs`, add a parser for the `skill.list` payload (keyed on `path`, since ids are
bare), and add the arm to the CI job. `plugins/soleur/test/harness-discovery-smoke.test.ts`'s
"unknown harness is named in the error" case currently asserts `opencode` is refused and must move
to a still-refused name.

### TR7: Manifests, parity census, and the `@` sigil

- Add an OpenCode install artifact (`opencode/opencode.json` config fragment declaring the
  canonical `skills` roots and `instructions`), the peer of `.cursor-plugin/plugin.json`.
- `harness-parity.ts` `POPULATION_GLOBS` gains the OpenCode front-door globs
  (`opencode/agents/**/*.md`, `opencode/commands/*.md`), as the Codex/Devin front doors are already
  listed.
- **`@` sigil.** OpenCode invokes agents by `@`-mention; `@` is already outside `BOUNDARY` in
  `harness-parity.ts` and is therefore treated as a sigil, so `@…` sites need either canonical
  rewriting or a `harness-forms` region. ADR-226 §Consequences makes re-reading `BOUNDARY` an
  obligation as harnesses land; this spec records that the re-read was performed for OpenCode and
  `BOUNDARY` is **unchanged** — `@`, `/`, and `$` are already members of the sigil set it names, so
  no new character is admitted.

## Decisions

Technical forks are resolved here rather than carried as operator questions.

### D1 — Namespacing: accept bare ids; keep canonical docs on `soleur:<name>`

OpenCode's skill id is the bare directory basename and cannot be namespaced (measurement §2.3: the
skill name must equal its directory name). Soleur already has a harness with bare dispatch — Grok
exposes bare `/<skill>` and `normalizeSkillName` strips the prefix — so this is the existing
pattern, not a new exception. Canonical, agent-read docs keep `soleur:<name>` (ADR-226 census
unchanged); the `opencode` arm of `formatSkillInvocation` renders the bare form. The collision
surface with a user's own bare-named skills is **accepted and recorded**: no collision was observed
(measurement §2.3), and it is the same class Grok already carries.

### D2 — Agents: generator injects `mode: subagent`; ids are path-derived

Measured: without `mode: subagent`, every canonical agent registers as `primary` and is
unspawnable; `name:` frontmatter is ignored and the id is the path (measurement §3.0). The generator
therefore emits `mode: subagent`, `description:`, and a body pointing at the canonical agent file,
at a path that **is** the id (`opencode/agents/engineering/cto.md` → `engineering/cto`).

**Amended 2026-10-18 (§11.2).** The first draft also emitted `model: inherit`, reasoning that a
Claude SKU alias (`sonnet`, `opus`) must not leak and `inherit` was the measured-harmless literal
(§3.0). That reading is **refuted**: `inherit` is not an OpenCode `provider/model` id, and an agent
carrying it produces no document and **does not register at all** — with all 67 stubs emitting it,
`GET /api/agent` returned only the 7 built-ins. The generator now emits **no `model:` line**, which
is this harness's spelling of "inherits the session model" (a stub with `mode: subagent` and no
`model` registers with no `model` key and inherits, §11.2).

### D3 — Completion: there is no Stop hook, so structural checks are the contract

OpenCode V2 has no Stop hook (measurement §6.6). The complete hook surface is
`session(prompt | context | compaction | generate | title | model.request | http.request |
http.response | experimental.ws.* | retry)`, `permission.evaluate`, `shell.create.before`, and
`tool.execute.before | after` — each communicates only by mutating the event object it is handed —
and the event surface (`ctx.event.subscribe`) is a one-way iterator with no return channel. No hook
can defer a stop, force a continuation, or veto a completion. "Session went quiet" (`session.idle`,
and the `Session.Message.Idle` record) is therefore *observation only*, so the
`<promise>DONE</promise>` marker is downgraded to advisory on this harness and autonomous skills lean
on their already-preferred structural completion (exit codes, CLI-output checks — AGENTS.md's stated
preference, and the reason `/goal` was rejected). Following the Codex precedent, a gate with no
equivalent is **reported as unsupported, never silently skipped**.

### D4 — Compaction re-read is preserved; continuation is not (a split from Codex/Devin)

The checkpoint-summary boundary is reachable — `ctx.session.hook("compaction")`, and `context` runs
for every agent-loop request including tool-driven continuations (measurement §6.6) — so the
post-compaction re-read directive **can** be delivered here, unlike Codex and Devin where
`compaction-state.sh` has no equivalent. The **autocontinue** half does not survive: V2 has no
`experimental.compaction.autocontinue` hook and no hook can force a continuation, so the re-read
lands on the next real request instead of resuming a stop. `opencode/INSTRUCTIONS.md`'s "Hooks and
completion" section states exactly this split — re-read preserved, continuation not.

### D5 — Distribution: config fragment + plugin module

OpenCode has no declarative plugin manifest; its install surface is config plus a code plugin
(measurement §6.6, §10.0 item 8). The spec ships a generated `opencode/opencode.json` fragment (skills
roots, instructions) and a hand-written hook plugin module written against the V2 package,
`@opencode/plugin@2.0.32` — **not** `@opencode-ai/plugin`, which is the V1 package the runtime
rejects (§6.6). Both delivery routes for the module were measured to load: the global discovery
directory `<configdir>/plugins/*` with no config entry, and the `plugins` config key with a path
relative to the config file. The config fragment is generated; the module is adapter source.

## Unmeasured steps (gates to run, not questions to ask)

1. **Detection CLI-specificity** — prove `OPENCODE` is not set by a non-CLI OpenCode process
   (ADR-274's bar). Measurement §1.0 shows presence only.
2. **Hook firing end-to-end** — the credential guard and destructive-command guard actually
   dispatching under a live OpenCode plugin, captured the way Devin's envelope-capture was.

Closed since the first draft: **`session.idle` continuation** (§6.6 — no blocking Stop contract
exists, so D3's advisory downgrade is the final word) and the **hermetic install path** (§11.4,
§11.6 — a hermetic install from this checkout registers exactly the declared set).

## User-Brand Impact

The brand-survival threshold is **single-user incident**, matching ADR-274. The load-bearing risk
is the same shape: advertising harness support ahead of the measurement. Public README,
getting-started, comparison, blog, and battlecard pages stay unchanged until Acceptance Criteria
are met. On the flip, grep `knowledge-base/legal` for future-tense harness sentences and route hits
to the CLO — a harness adapter that a user installs and that silently does not classify the session
or fire its guards is a support failure dressed as a feature.

## Acceptance Criteria

Support is claimed only when all four are measured and quoted (ADR-274's shape):

- [ ] `/go` in an OpenCode session classifies the intent (session is `opencode`, not `unknown`).
- [ ] One pipeline skill completes its gates end to end under OpenCode.
- [ ] One agent spawn runs, or is refused in words — never silently absent.
- [ ] Each shipped guard (credential, destructive-command) fires.
- [ ] `harness-discovery` OpenCode arm passes on a hermetic fixture and reds on a dropped
      declared root.
- [ ] The generator's `--check` mode is green in CI (no drift).
- [ ] `harness-parity` census and its tree tests pass with the new front-door globs.

## Test Scenarios

- `detectHarness({OPENCODE:"1"})` → `opencode`; a plain env → unchanged.
- `formatSkillInvocation("soleur:plan")` under `opencode` → `plan` (bare).
- Generator `--check` fails on a hand-edited stub and on a missing stub.
- `harness-discovery-smoke` OpenCode parser: a `skill.list` payload keyed on `path` distinguishes
  the canonical registrations from global ones; a shrunken listing exits 1 naming the loss; an
  unreadable payload exits 3.
- `harness-parity` census over the OpenCode front-door globs reports the same canonical ids as the
  Codex/Devin front doors.

## References

- `knowledge-base/project/specs/feat-opencode-harness/measurements.md` — every measured fact above.
- `knowledge-base/engineering/architecture/decisions/ADR-245-retire-openhands-gemini-ports-and-prove-codex-devin-discovery-in-ci.md` — re-entry criterion, CI vendor-pin policy, exit taxonomy.
- `knowledge-base/engineering/architecture/decisions/ADR-274-add-a-cursor-cli-plugin-adapter.md` — slice-1 precedent, detection-measurement rule.
- `knowledge-base/engineering/architecture/decisions/ADR-226-canonical-component-references-in-plugin-docs.md` — canonical component refs, `BOUNDARY` re-read obligation.
- `knowledge-base/engineering/architecture/decisions/ADR-223-per-harness-hook-registries-with-a-disposition-ledger.md` — per-harness hook registries.
- `knowledge-base/engineering/architecture/decisions/ADR-110-harness-semantic-model-tier-map.md` — semantic tier map.
- `plugins/soleur/lib/harness.ts`, `harness-parity.ts`, `harness-tool-map.ts`, `harness-model-map.ts`, `workflow-fidelity.ts`.
- `plugins/soleur/scripts/sync-grok-agent-compat.ts`, `sync-cursor-name-map.ts` — generator precedents.
- `plugins/soleur/codex/INSTRUCTIONS.md`, `plugins/soleur/devin/INSTRUCTIONS.md` — adapter-doc precedents.
- `knowledge-base/project/specs/external/opencode.md` — prior V1 vendor reference (2026-01-21); superseded where it disagrees with this spec's measurements.
