---
title: Add an OpenCode plugin adapter
status: adopting
date: 2026-10-17
supersedes: none
related_adrs: [ADR-110, ADR-179, ADR-215, ADR-223, ADR-226, ADR-245, ADR-274]
tags: [harness, opencode, plugin]
brand_survival_threshold: single-user incident
---

# ADR-291: Add an OpenCode plugin adapter

## Status

**Adopting — generator landed 2026-10-19** (`plugins/soleur/scripts/sync-opencode-adapter.ts`, drift-gated by
`plugins/soleur/test/opencode-adapter-drift.test.ts`), per the condition this record set for itself. Flips to
`accepted` when the support bar below is met. In this record, **harness** means the `Harness` union in
`plugins/soleur/lib/harness.ts`. The word is not in `knowledge-base/project/glossary.md`.

Ordinal census on 2026-10-17, after `git fetch origin --prune`, over `refs/heads` and
`refs/remotes/origin`: ADR-291 was unused. The highest ordinal present is ADR-290, carried only by
`feat-one-shot-10331-pr3a-ruff-eslint-scope` and its origin ref. The checked-out tree holds up to
ADR-288. ADR-289 and ADR-290 are taken, so this record does not reuse them; no citation of 291
exists in the corpus.

Every OpenCode fact below is measured in
`knowledge-base/project/specs/feat-opencode-harness/measurements.md` and cited by anchor. Do not
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

The adapter is supported only when a committed shape note quotes all four of: `/go` classifies the
session as `opencode`, one pipeline skill finishes its gates, one agent spawn runs or is refused in
words, and each guard fires (ADR-274's bar).

`BOUNDARY` in `harness-parity.ts` is **unchanged**. ADR-226 §Consequences makes re-reading it an
obligation as harnesses land; the re-read was performed for OpenCode and admits no new character —
`@`, `/`, and `$` are already named as sigils. The consequence is recorded rather than fixed here:
OpenCode invokes agents by `@`-mention, so an `@…` reference site is classified as a sigil and needs
either canonical rewriting or a `harness-forms` region.

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

The plugin pin is `@opencode/plugin@2.0.32` — the V2 package, version-matched to the CLI. It is
**not** `@opencode-ai/plugin@1.19.3`: that is the V1 package, and the 2.0.32 runtime rejects the V1
module shape outright (`Plugin must export a default definition with an id and an effect or setup
function`, §6.6 arm A). The V2 module is `export default { id, async setup(ctx) { … } }`. Both
delivery routes were measured to load — the global discovery directory `<configdir>/plugins/*` with
no config entry, and the `plugins` config key with a config-relative path (§6.6 arms B/C). The pin is
a vendor-pin and inherits ADR-245's CI vendor-pin policy.

Public README, getting-started, comparison, blog, and battlecard pages stay unchanged until the
support bar is met. When the status flips to `accepted`, grep `knowledge-base/legal` for future-tense
sentences about the harness list and route hits to the CLO; do not edit those pages in the flip
commit without that review.

## Cost Impacts

None. No new Soleur subscription, no new credential, no new paid vendor — the operator's existing
OpenCode install is the host. Model tiers resolve to the operator's own provider credentials.

## NFR Impacts

None. No NFR register row changes tier, no new Sentry monitor, no soak. The one observability touch
is the CI discovery arm, which is a gate and not a runtime monitor.

## Principle Alignment

AP-004 (Agent-native parity): Aligned — the same lifecycle skills are reachable from OpenCode once
the support bar is met.

AP-006 (All knowledge in committed repo files): Aligned — the generated tree and config fragment are
committed and drift-checked.

AP-007 (Exhaust automation before manual steps): Aligned — agents and commands come from the
generator with a `--check` gate, not a hand-copied tree.

AP-008 (Doppler for secrets): N/A — no new secret.

AP-011 (ADRs for architecture decisions): Aligned — this record is the decision.

AP-012 (New vendor checklist): N/A — no Soleur-paid vendor and no new vendor environment variable.
OpenCode is the operator's own tool, not a Soleur processor.
