---
title: Add an OpenCode plugin adapter
status: accepted
date: 2026-10-17
supersedes: none
related_adrs: [ADR-110, ADR-179, ADR-215, ADR-223, ADR-226, ADR-245, ADR-274]
tags: [harness, opencode, plugin]
brand_survival_threshold: single-user incident
---

# ADR-291: Add an OpenCode plugin adapter

## Status

**Accepted 2026-10-20** — the adapter shipped in `v3.342.0` (PR #10571, merge commit `95562f22ffb4`), and the
support bar below is met: all four ADR-274 points are quoted, in full, in
`knowledge-base/project/specs/archive/20261019-180200-feat-opencode-harness/SHAPE-NOTE.md`. At accept time two
of the four (§7.1.2 a pipeline skill's gates, §7.1.3 a live agent spawn) were quoted on **substituted
evidence** — a routed call completing after a guard block and the `spawnAgent()` dispatch shape — because the
probe host carried no provider credentials for a hermetic OpenCode session; the reproduction was tracked in
#10591 item 1. That substitution was a disclosed gap in the evidence, not in the adapter, and it is why this
record could be `accepted` while **no public "supports OpenCode" claim was made**: the accept-time
future-tense sweep of `knowledge-base/legal` and `docs/` for support-OpenCode sentences returned zero hits to
route to the CLO.

**The substitution is closed (2026-10-22).** Both points were reproduced live and quoted in SHAPE-NOTE §7.1.6
(merged in #10745, commit `06836baf90ec`), so all four ADR-274 points now rest on live captures; §7.1.6
carries the run-traceability disclosures.

**No public claim is made yet, and the gate on one is editorial.** A repo-wide sweep on 2026-10-22 found
OpenCode on the public pages named below only as a third-party reference inside one comparison post. The
accepted text said those pages were "unchanged" — a proxy rather than the fact: #10725 (`3bf4f18ac7ee`,
2026-10-20) rewrote `README.md` and the getting-started, index, pricing, and `llms.txt` pages with
multi-harness install instructions naming Claude Code, Grok Build, Codex, and Devin CLI. The load-bearing fact
is the claim, and none of those pages makes it. What remains is a brand-level editorial decision rather than
an evidence question. Flipping it is a separate, deliberate change, and it routes to the CLO first: this
feature's legal gate (§7.2.1 of its `tasks.md`) requires CLO review before any edit to those canonical pages,
ADR-274 set the same rule for its own harness flip, and the CLO attestation pins the four-member parenthetical
on them (`including Claude Code, Grok Build, Codex, and Devin CLI`) — non-exhaustive, so a fifth member does
not falsify it, but editing it is the canonical-page edit that routes to the CLO. This Status entry will be
updated by that flip.

In this record, **harness** means the `Harness` union in `plugins/soleur/lib/harness.ts`. The word is not in
`knowledge-base/project/glossary.md`.

Superseded status, kept so the condition this record set for itself stays auditable: **Adopting — generator
landed 2026-10-19** (`plugins/soleur/scripts/sync-opencode-adapter.ts`, drift-gated by
`plugins/soleur/test/opencode-adapter-drift.test.ts`). It flipped to `accepted` when the support bar below was
met.

Ordinal census on 2026-10-17, after `git fetch origin --prune`, over `refs/heads` and
`refs/remotes/origin`: ADR-291 was unused. The highest ordinal present was ADR-290, carried only by
`feat-one-shot-10331-pr3a-ruff-eslint-scope` and its origin ref. The checked-out tree held up to
ADR-288. ADR-289 and ADR-290 are taken, so this record does not reuse them; no citation of 291
existed in the corpus.

Every OpenCode fact below is measured in
`knowledge-base/project/specs/archive/20261019-180200-feat-opencode-harness/measurements.md` and cited by anchor. Do not
restate its numbers here.

## Context

An operator who already runs Soleur in Claude Code, Grok Build, Codex, or Devin cannot run the same
lifecycle in OpenCode V2. `Harness` has no `opencode` member, so that session is `unknown`, and the
unknown instructions name the Skill tool and the Task tool in Claude's vocabulary.

OpenCode V2 is a different host from Cursor. Measured (measurements §2.2), it consumes Soleur's
**canonical** `plugins/soleur/skills` tree directly through the `skills` config key — 103 skills
registered with no copy. Its per-harness surface is therefore *narrower* than Cursor's: agents and
commands need a generated tree, skills do not. This is the ADR-215 shape — a per-harness plugin that
reuses the canonical Soleur components — extended to a host that needs even less translation than
Codex did.

Three measured shapes drive the decision:

1. **Skill ids are bare.** The skill name must equal its directory name and match
   `^[a-z0-9]+(-[a-z0-9]+)*$` (§2.3). There is no namespace segment, so OpenCode cannot express
   `soleur:<name>` as a skill id, and Soleur cannot prefix without renaming canonical directories.
   Grok already dispatches bare and strips the prefix (`normalizeSkillName`), so this is an existing
   pattern, not a new exception.
2. **Agents default to `primary`.** Every canonical agent registered as unspawnable until
   `mode: subagent` was injected (§3.0). The agent id is path-derived with `/` and the frontmatter
   `name:` is ignored (§3.0). `model: inherit` resolves to null — the session model (§3.0).
3. **There is no Stop hook.** OpenCode V2's complete hook surface — `session(prompt | context |
   compaction | generate | title | model.request | http.request | http.response |
   experimental.ws.* | retry)`, `permission.evaluate`, `shell.create.before`, and
   `tool.execute.before | after` — communicates only by mutating the event object it is handed, and
   `ctx.event.subscribe` is a one-way iterator with no return channel. No member of it can defer a
   stop, force a continuation, or veto a completion (§6.6). "Session went quiet" is an observation,
   not a boundary.

## Considered Options

- **Adapter that consumes the canonical skill tree and generates only agents and commands.** Pros:
  the smallest generated surface of any harness; the skill half of ADR-245's drift obligation
  disappears because there is nothing to drift. Chosen.
- **Generate a per-harness skill copy under `plugins/soleur/opencode/skills/`.** Pros: uniform with
  Codex and Devin. Cons: measured unnecessary (§2.2), and it re-creates exactly the drift surface
  ADR-245 deleted. Rejected.
- **Prefix OpenCode skill ids as `soleur-<name>`.** Pros: removes the collision surface bare ids
  carry. Cons: the id must equal the directory name (§2.3), so this renames the canonical tree and
  breaks the ADR-226 census and every `soleur:<name>` reference. Rejected — Grok already accepts the
  bare-dispatch class.
- **Enforce the completion marker with a blocking Stop equivalent.** Pros: parity with
  `stop-hook.sh`. Cons: there is no blocking stop contract to use — the hook surface is enumerated
  in full and none of it can veto or continue a stop (§6.6); building one is a claim, not a
  measurement. Rejected — the Codex posture applies: report the unsupported gate, never simulate it.
- **Call the adapter supported when the mapping doc exists.** Pros: the work closes faster. Cons: a
  session would still be `unknown` and no guard would have fired. Rejected on the ADR-274 precedent.

## Decision

OpenCode V2 is a host runtime with a native skills surface, a generated agent and command tree, a
config fragment, and a hook plugin.

`Harness` gains an `opencode` member. `detectHarness` grows a predicate on the measured `OPENCODE`
marker (§1.0) — **and only after that marker is shown not to be set by a non-CLI OpenCode process**.
`AI_AGENT=opencode` is corroboration, never the predicate: its name is generic (§1.0).

The canonical tree stays the source. The generator emits, and nothing is hand-copied:

| Artifact | Generated? | Reason |
|---|---|---|
| Skills | **No** | canonical tree registers via the `skills` config key (§2.2) |
| `plugins/soleur/opencode/agents/**/*.md` | Yes | `mode: subagent` + path id + description (§3.0) |
| `plugins/soleur/opencode/commands/*.md` | Yes | OpenCode reads its own commands dir (§4.0) |
| `plugins/soleur/opencode/INSTRUCTIONS.md` | Yes | tool/path mapping doc |
| `plugins/soleur/opencode/opencode.json` | Yes | skills roots + instructions fragment |
| `plugins/soleur/opencode/*.ts` (hook plugin) | **No — source** | adapter logic, like `harness.ts` |

Skills are dispatched by bare id; the `opencode` arm of `formatSkillInvocation` renders the bare
form and canonical, agent-read docs keep `soleur:<name>` (ADR-226 census unchanged). Agent identity
is the path id (`engineering/cto`), never the registry id or the ignored `name:` field. Every
generated agent carries `mode: subagent`.

There is no Stop hook to stand in for. The `<promise>DONE</promise>` marker is **advisory** on
OpenCode and autonomous skills rely on their structural completion checks (exit codes, CLI-output
checks) — AGENTS.md's stated preference. This is the final word and not a placeholder: the hook
surface is enumerated in full (§6.6) and no member of it can block or continue a stop, so no later
phase may upgrade the marker to a contract without new measurement.

Compaction splits. The post-compaction re-read directive **is** deliverable —
`ctx.session.hook("compaction")` observes the checkpoint, and `context` runs for every agent-loop
request including tool-driven continuations (§6.6) — unlike Codex and Devin, where
`compaction-state.sh` has no equivalent. The **autocontinue** half is not: V2 has no
`experimental.compaction.autocontinue` hook and nothing can resume a stop, so the re-read lands on
the next real request rather than by continuation.

Every OpenCode hook gets a disposition row in its own registry (ADR-223). There is no plugin-root
fallback (ADR-179). The install surface is a config fragment plus a plugin module, because OpenCode
has no declarative plugin manifest (§6.1, §10.0 item 8).

The guards bind at `permission.evaluate`, the one hook surface with a blocking channel. Its event
carries the tool as `action` and the command as `resources[0]`, with a mutable
`effect: allow | ask | deny` plus `message`; setting `deny` ends the tool as `permission.rejected`
carrying the reason, and `ask` holds it open for a person (both measured live, §12.2). So a guard's
`deny` blocks and its `ask` prompts, and **neither is downgraded**. An earlier design in this ADR's
implementation bound `tool.execute.before` and delivered `ask` as a refusal-with-reason; it is
withdrawn as measured-false, because that surface fires *before* `permission.evaluate` and can only
refuse by throwing, so it would preempt the true ask behind it. Two corrections arrived with it
(§12.1): the shell tool's wire name is **`shell`**, not `bash` — a map keyed on `bash`
alone never matches and the guards decline silently — and code-mode `execute` calls carry JavaScript
rather than a command, so the Bash guards do not reach them. (`bash` was not a mistake in the docs:
§12.8 measures `/docs/*` as the V1 tree and `/v2/docs/*` as V2's, and only the V1 tree says `bash`.
The plugin maps both spellings, which is a V1-compatibility shim rather than a docs workaround.)
`operator-stage-approval.sh` still
cannot be bound: it needs a rewritten command and an ask in the same decision, and
`permission.evaluate` types `resources` as readonly while `tool.execute.before` cannot prompt.

Two generated surfaces carry the harness translation, and both are pinned against the corpus rather
than against their generator. `opencode/INSTRUCTIONS.md` gains a `## Tools` table over the closed
`CLAUDE_CODE_TOOLS` vocabulary, and `test/harness-tool-map.test.ts` now asks its completeness
question of **every** adapter table instead of two — so a name the corpus uses with no OpenCode row
reds, naming the skill and line. The OpenCode side is the measured V2 built-in set, including
`subagent` for agent spawning, `skill` keyed on the bare id, and the absent set (`todo`, an await
primitive, the cron/push/schedule family) stated as unsupported rather than omitted (§12.8).
`TIER_MAPS` gains an `opencode` row: `cheap` → `opencode/glm-5.3-flash-free` and
`standard`/`strong`/`advisor` → `opencode/big-pickle`, the id this measurement session itself runs
on. The binding constraint is availability, not price — a keyless install advertises only the Zen
free set, and ADR-053's absolute-pin rule is satisfiable only where the SKU is always present — so
the paid Zen rows and the NVIDIA trial endpoints (logged, trial-use only) are rejected on the record
(§12.7). The row is expected to need bumping, which is what the table is for.

The adapter is supported only when a committed shape note quotes all four of: `/go` classifies the
session as `opencode`, one pipeline skill finishes its gates, one agent spawn runs or is refused in
words, and each guard fires (ADR-274's bar).

`BOUNDARY` in `harness-parity.ts` is **unchanged**. ADR-226 §Consequences makes re-reading it an
obligation as harnesses land; the re-read was performed for OpenCode and admits no new character —
`@`, `/`, and `$` are already named as sigils. The re-read's other half is a measurement rather than
a judgment: the generated tree was grepped for `@`-mention sites and **carries none** (`grep -rn "@"
plugins/soleur/opencode/{agents,commands}` is empty), which is what makes the unchanged set a
decision rather than a deferral. Were a site to appear, OpenCode invokes agents by `@`-mention and
the site would classify as a sigil, needing either canonical rewriting or a `harness-forms` region.

Two globs join the population: `opencode/agents/**/*.md` (policy `agent`) and
`opencode/commands/*.md` (policy `command`). They are the OpenCode *front doors* — the only harness
whose shims are generated prose rather than a copy of the skill tree, because OpenCode registers the
canonical `skills/` directory through a config key. Leaving them out is the shape of gap that reads
as coverage: the generator could emit a non-canonical id and every gate would stay green while the
spawn failed in a live session. `opencode/INSTRUCTIONS.md` stays OUT deliberately and for the same
reason `codex/INSTRUCTIONS.md` and `devin/INSTRUCTIONS.md` do — measured, all three carry the
*typed* slash form as their subject (`/go`, `/soleur:go`), which is the "human-typed entry point"
class ADR-226 §4 exempts per harness. The tree test pins the generated set to the registry **by
path**, not only by count, so a stale stub for a renamed agent reds.

## Consequences

The generator is the maintenance surface and carries a `--check` mode that fails CI on drift, so a
canonical agent added without regenerating its OpenCode stub reds rather than silently missing.

`plugins/soleur/test/harness-discovery-smoke.test.ts` names `opencode` as the *refused* harness in
its "unknown harness" case; that case moves to a still-unknown name (`cursor`). The discovery arm
keys on `path`, not `name`, because ids are bare basenames and the listing is polluted by the
operator's global skill roots when `HOME` is not controlled (§9.0). It inherits ADR-245's exit
taxonomy — 3 for unresolved or unreadable, 1 for measured loss.

Two implementation findings, both from building the arm (§11.6), make the OpenCode arm's shape
differ from the Codex/Devin arms and are recorded here so they are not "simplified" back:

- The listing is built by an asynchronous scan, so the arm POLLS until the expected population is
  reached. A single read reports a correct install as a total loss; `POST /api/location/reload` is
  not the fix (it clears the listing before rebuilding it).
- The payload must be read from a FILE. `execFileSync`'s pipe silently truncates a large stdout
  (~0.8–0.9 MB, varying) and reports success, which grades a correct install UNRESOLVED.

There is **no vendor pin, because there is no vendor dependency**. The V2 loader accepts a plain
default-exported object (measurement §6.6 arms B/C), so the plugin module imports only `node:`
builtins and no vendor package is on its import graph. The V1 package `@opencode-ai/plugin@1.19.3`
remains the wrong generation — the 2.0.32 runtime rejects the V1 module shape outright (`Plugin must
export a default definition with an id and an effect or setup function`, §6.6 arm A) — and the V2
module shape is `export default { id, async setup(ctx) { … } }`. Both delivery routes were measured
to load: the global discovery directory `<configdir>/plugins/*` with no config entry, and the
`plugins` config key with a config-relative path (§6.6 arms B/C). ADR-245's vendor-pin policy is
satisfied vacuously, and a pin added back "for safety" would be a dependency the loader never asked
for.

None of the public README, getting-started, comparison, blog, or battlecard pages claims OpenCode support —
repo-wide sweep, 2026-10-22. The flip to
`accepted` (2026-10-20) required grepping `knowledge-base/legal` and `docs/` for future-tense sentences
about supporting OpenCode and routing hits to the CLO; that sweep returned **zero** hits — this is empty:

`grep -rniE "(will|going to|plans to|soon|future) support (the )?opencode" knowledge-base/legal/ docs/`

so there was nothing to route and nothing to review. See Status: the evidence no longer holds the pages back,
and the claim flip is a separate, deliberate brand-level change that routes to the CLO first.

## Cost Impacts

None. No new Soleur subscription, no new credential, no new paid vendor — the operator's existing
OpenCode install is the host. Model tiers resolve to the operator's own provider credentials.

## NFR Impacts

None. No NFR register row changes tier, no new Sentry monitor, no soak. The one observability touch
is the CI discovery arm, which is a gate and not a runtime monitor.

## Principle Alignment

AP-004 (Agent-native parity): Aligned — the same lifecycle skills are reachable from OpenCode; the
support bar was met 2026-10-20 (see Status).

AP-006 (All knowledge in committed repo files): Aligned — the generated tree and config fragment are
committed and drift-checked.

AP-007 (Exhaust automation before manual steps): Aligned — agents and commands come from the
generator with a `--check` gate, not a hand-copied tree.

AP-008 (Doppler for secrets): N/A — no new secret.

AP-011 (ADRs for architecture decisions): Aligned — this record is the decision.

AP-012 (New vendor checklist): N/A — no Soleur-paid vendor and no new vendor environment variable.
OpenCode is the operator's own tool, not a Soleur processor.
