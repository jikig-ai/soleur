# ADR-226: Component references in plugin docs are canonical `soleur:<name>`; harness forms are the adapter's to render

- **Date:** 2026-09-18

## Status

Accepted.

## Context

Soleur ships one component tree — 98 skills, 3 commands, 67 registry agents — to
four harnesses that each invoke a component with their own syntax:

| Harness | Skill form | Agent form |
| --- | --- | --- |
| Claude Code | Skill tool, `soleur:<name>` | Task tool, registry id |
| Grok Build | Read `plugins/soleur/skills/<name>/SKILL.md` in-process; `/<name>` names it | `spawn_subagent` with the hyphen stem `soleur-a-b` |
| Codex | `$soleur:<name>` via `skills.read` | `spawn_agent` with canonical instructions |
| Devin CLI | `/soleur:<name>` slash command | `run_subagent` with the registry id |

The adapter that knows those forms is `plugins/soleur/lib/harness.ts`
(`formatSkillInvocation`, `invokeSkill`, `spawnAgent`) and, since this decision,
`workflow-fidelity.ts` (`formatSkillRef`). Every harness already resolves the
canonical shape: `codex/INSTRUCTIONS.md` and `devin/INSTRUCTIONS.md` each carry
a `Skill soleur:<name> → form` row, `commands/go.md` Step 2.0 carries the routing
contract for `/go`-entered sessions, and Claude resolves it natively.

The docs did not. Measured on 2026-09-18 with the classifier this ADR introduces:
**1029 non-canonical sites in 62 of the 106 docs** an agent reads on every
harness (`skills/*/SKILL.md`, `commands/*.md`, the Codex and Devin skill
wrappers). 488 were bare agent leaves (`Task git-history-analyzer(…)`) — a
spawn that is dead on Grok because `agentIdToGrokSubagentType("cpo")` is `cpo`
and no `.grok/agents/cpo.md` exists; 339 were the Grok slash (`/plan`); 187
the Claude/Devin slash (`/soleur:plan`); the rest `@agent-` mentions, `$soleur:`
and a hyphen stem in prose. A self-hosted operator on a non-Claude harness
following that prose names a form their harness does not have, hits nothing,
and has no signal that anything was wrong (#8299).

Two designs were built and refuted before this one (plan v1, v2 in
`knowledge-base/project/plans/2026-09-18-feat-harness-parity-census-plan.md`).
v1 asserted a marker was *present* — it certified how an agent arrived, not what
the doc told it to invoke next. v2 asserted a *blocklist* of harness tokens was
absent — and omitted the Grok branch of `formatSkillInvocation`, defined eight
lines from a form it had captured. Both measured the instrument carefully and the
predicate wrongly. AP-025 names the shape: a state predicate is complete by
construction; a list of ways to reach it cannot be proven complete.

## Considered Options

- **Option A: marker-presence census (v1)** — assert every doc carries a
  `grok-harness-invoke` preamble. Pros: cheap; the 12 pipeline carriers already
  have one. Cons: proves arrival, not the next dispatch; the 86 non-carrier
  skills would need a template pin that certifies nothing about their prose.
- **Option B: harness-token blocklist (v2)** — forbid `/name`, `/soleur:name`,
  `$soleur:name`, `@agent-`. Pros: direct. Cons: the list is open — it missed a
  form defined in the adapter it was copied from; every new harness or sigil
  reopens it; a `/kb-search` shape the list did not name passed green.
- **Option C: allowlist over the derived name index (chosen)** — enumerate what
  a doc MAY do with a known name (canonical id at a prose boundary, bare skill
  name in prose, path component) and call anything else non-canonical. Pros:
  closed by construction — the index is `git ls-files` with `:(glob)` plus
  `discoverAgentPaths()`, never listed; a novel sigil (`%plan`) is caught without
  being named. Cons: two allowlists (the boundary set and the path class) become
  verdict-deciding constants that need permanent fixtures; bare agent leaves in
  prose (488 sites) are gated at the operator's decision, which doubled the
  remediation.
- **Option D: per-doc census vector with `--update`/`--check`** — pin per-doc
  counts and ratchet. Rejected by both review panels and the operator: the
  property is absolute (`NONCANONICAL == []`), so there is no number to pin, and
  a baseline is the compensation surface v2's scalar snapshot already showed.
- **Option E: strip fenced code and marker lines before classifying** — 16 fenced
  blocks are dispatch payloads an agent executes, and wildcard marker stripping
  is a laundering channel. Fences are classified like prose; one exempt region
  kind exists, under `commands/` only, with a strict marker grammar.

## Decision

Option C. `plugins/soleur/lib/harness-parity.ts` is the classifier;
`plugins/soleur/test/harness-parity-tree.test.ts` is the gate;
`plugins/soleur/scripts/harness-parity-census.ts --report | --fix` is the
author's loop.

1. **Canonical shapes and permitted contexts.** A skill or command is named
   `soleur:<name>`; an agent is named by its registry id
   (`soleur:engineering:review:security-sentinel`). A known name may appear as
   that canonical id at a prose boundary (R2), as a bare **skill** name in prose
   (R6 — skill names are English words), or as a path component (R7). Every
   other context is non-canonical: a sigil before a known name (R1, R8), the
   namespace inside a token (R4), a Grok hyphen stem (R5), a bare **agent** leaf
   (R6b — never a prose word, and dead on Grok), a sigil absorbed into a
   hyphenated token (R9). The boundary set and the path class are allowlists;
   an author who collides with one (a shell `$work`, a glob `"$d"/rclone-*`)
   braces or renames the identifier — the boundary set is never widened to admit
   a sigil.
2. **Population and index are derived, never listed.** Population:
   `:(glob)plugins/soleur/{skills,codex/skills,devin/skills}/*/SKILL.md` and
   `:(glob)plugins/soleur/commands/*.md`, each glob carrying its region policy.
   Index: the skill directories, the command basenames, and
   `discoverAgentPaths()` mapped through `pathToAgentId` — the registry Grok's
   compat stubs are generated from, which excludes `README*` and `references/`.
   The two glob sets are separate constants so an empty population throws
   `0 docs examined` rather than failing the index invariant.
3. **One exempt region kind, commands only, strict grammar.**
   `<!-- harness-forms:start -->` … `<!-- harness-forms:end -->` is honoured
   where the region policy is `command`; its subject is the per-harness forms
   themselves (go.md Step 2.0's table, the Devin/Grok dispatch bullets, the
   "Grok entry is `/go`" sharp edge). A marker is a whole line matching the
   strict form byte-for-byte; a loose match (case, CRLF, inline text) is a RED
   malformed marker; markers with any other name are transparent content.
   `commands/help.md` is excluded by path with the reason stated: its subject is
   the typed forms, and wrapping 117 of its 155 lines would be a whole-file
   exemption wearing markers.
4. **Agent-read prose is canonical; human-typed entry points are enumerated per
   harness by design.** `README.md`, `docs/**`, `llms.txt`, `help.md` and the
   harness INSTRUCTIONS files are read by a person who types the form, so the
   slash form is right there. Operator-pasted prompts that a skill *emits* (a
   resume prompt after `/clear`, "dispatch the cron via …") stay canonical in the
   doc and render at emit time: the emitting step renders the entry as the
   active harness's operator-typed form per `formatSkillInvocation` before
   printing — `/soleur:plan #123` on Claude, `/plan #123` on Grok,
   `$soleur:plan #123` on Codex.
5. **`/go` is the Grok entry.** A skill entered directly on Grok has only its
   own preamble in context, so the 12 `grok-harness-invoke` carriers state the
   general rule — *any `soleur:<name>` in this document names a skill; on Grok
   Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process* — and
   Guard 1 in `workflow-fidelity.test.ts` pins it. The other 86 skills rely on
   `/go` having run (go.md's sharp edge already says so).
6. **Born blocking, no baseline.** The gated property is absolute. What can go
   quietly blind is the instrument, and each blindness has a permanent,
   independent check: an index invariant computed from the tree test's own
   literal pathspecs (`|AGENTS| === EXPECTED_SOLEUR_AGENT_COUNT`, leaves unique
   and disjoint from skill names); the `0 docs examined` throw; 28 synthesized
   fixtures pinning every rule, both allowlists, the token class, the trailing
   glue strip and the marker grammar; and a cross-file sentinel — the fixture
   suite asserts the tree file contains the literal
   `expect(noncanonical).toEqual([])`.

The adapter's own fidelity strings are part of the decision: `workflow-fidelity.ts`
used to emit `/postmerge`, `/ship`, `/work` on every harness, so
`invokeSkill("ship")` on Codex said "invoke /postmerge". Every fidelity string
now goes through `formatSkillRef(skill, harness)`.

## Consequences

Easier: a doc that names a component names it once, in the one shape every
adapter resolves; a new harness is an adapter branch, not a doc sweep; a novel
sigil is caught without being named; the gate's failure message names the site,
the harness form it found, the canonical id to write, and `--fix`.

Harder: 81 lines with a slash form entered this population in the 30 days before
this decision, so authors will feel the gate — `--fix` repairs the mechanical
shapes (`/soleur:x`, `$soleur:x`, `@agent-soleur:x`, grok `/x`) and the
authoring surfaces (`skill-creator`, `compound-capture` Step 8, `heal-skill`)
teach the canonical form. Bare agent leaves are hand edits: the registry id is
longer and the sentence around it changes.

Declared gaps, each with an issue:

- **NG-M** (#8318): bare mechanism nouns (`Skill tool`, `Task tool`,
  `subagent_type`) that carry no name through a sigil — 82 lines in 29 docs. No
  canonical word exists to allowlist against; the adapters translate the noun
  themselves.
- **NG-P** (#8317, P1): other agent-read docs — agent bodies (35 sites / 15
  docs) and `skills/*/references/**` (44 / 19) — are one glob line each.
  Human-read surfaces stay out by design (§4).
- The dual-voice `**Grok:** Read plugins/soleur/skills/<x>/SKILL.md in this
  process` lines (20 in 7 docs) are PATH by design — a file path resolves on
  every harness, and `workflow-fidelity.test.ts` requires them.
- `soleur:<unknown>` is reported, not gated; a typo is a different defect. The
  set is diffed pre/post remediation so a hand rewrite cannot go quietly green.
- "Canonical resolves on every harness" is verified on Grok (`grok-fidelity`)
  and Claude; Codex and Devin are declared uncovered (#8306). The gate's promise
  is "no harness-specific form in agent-read prose", not "resolves everywhere".

Honest limit: moving go.md's region markers to enclose a dispatch line is
visible only in diff review — one file, one region kind, markers in the diff.
No hash is claimed to catch it; a registry that carries its own hash certifies
itself.

## Cost Impacts

None. One more `bun test` file in the existing `plugin-component-test` and CI
`test-bun` runs (~1 s over 106 docs).

## NFR Impacts

None directly. The gate protects the same surface AP-025's other walkers do —
that a committed artifact carries the property, rather than an interceptor
enumerating the ways to violate it.

## Principle Alignment

- AP-025 (State predicates, not reach-lists): Aligned — the classifier is an
  allowlist over a closed index, gated at commit time by a walker over every
  member; this is the canonical instance for prose.
- AP-011 (ADRs for architecture decisions): Aligned — this ADR reverses two
  refuted designs, which is the rich-shape trigger.

No new principle row: AP-025 already states the rule; this ADR is its
application to doc prose.

## Verification

- `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/harness-parity-tree.test.ts`
  — fixtures plus the tree census; the tree test prints
  `106 docs examined, 0 non-canonical, <n> canonical, <m> unknown-ns`.
- `bun plugins/soleur/scripts/harness-parity-census.ts --report` — `0 sites`
  on the remediated tree; on the pre-remediation tree it printed the 1029 / 62
  figure above (recorded in
  `knowledge-base/project/specs/feat-harness-parity-gate-8299/census-baseline.md`).
- Guard 3 mutation matrix N1–N13 and harness rows H1–H5 (plan v3 §Guard
  Contract), each run against a pristine copy and recorded in PR #8300.
