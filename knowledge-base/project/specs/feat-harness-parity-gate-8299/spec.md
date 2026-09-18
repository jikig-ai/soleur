---
title: Cross-harness parity census for skill invocation forms
feature: feat-harness-parity-gate-8299
date: 2026-09-18
closes: 8299
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-18-cross-harness-parity-gate-brainstorm.md
plan: knowledge-base/project/plans/2026-09-18-feat-harness-parity-census-plan.md
adr: ADR-226
status: active
---

# Spec — Cross-harness parity census

## Problem Statement

Soleur ships one component tree to multiple agent harnesses, but nothing requires a
skill edit to consider a harness other than the author's own, and nothing detects a
forgotten one. A Claude-only `/soleur:trigger-cron` invocation form was written into a
plan and its `tasks.md` and passed **every** existing gate — markdown-lint, the
guard-contract lint, the infra lint, a seven-agent review panel, and
`plugin-component-test`'s 2,889 tests. The operator caught it by eye.

Harness-specific prose is invisible to every gate in the repository.

Measured 2026-09-18 against `origin/main`: of 98 skills, **46 contain an invocation
instruction** and only **12** name the Grok form. **Codex is named by zero markers and
zero skills.** The existing partial guard
(`plugins/soleur/test/devin-cloud-mode.test.ts:450`) asserts marker-block
byte-identity over a **hand-listed** `UNION` array — the population shape ADR-193 §5
forbids.

## Goals

- G1 A born-blocking census over **all 98** tracked skills, population directory-derived.
- G2 Every skill resolves to QUALIFIED / AUTO-EXEMPT / UNCLASSIFIED. UNCLASSIFIED must be 0.
- G3 Replace the hand-listed `UNION` array with a derived population (ADR-193 §5).
- G4 Floors that catch extractor blindness: a qualified-count floor (grows only) and an
  **auto-exempt ceiling** (shrinks only), so a newly added skill is RED-by-default.
- G5 An auditable exemption ledger: dated, issue-linked, falsifiable reasons.

## Non-Goals

- NG1 **Mirror completeness** for the hand-ported trees (`.openhands/skills/` at 63/68
  agents, `.gemini/` at 1/68 agents + 3 skills). Deferred to **#8306**.
- NG2 **Migrating the ~105 `${CLAUDE_PLUGIN_ROOT:-…}` sites.** Owned by ADR-179 and
  open **#7453**. This work must not bless a `:-` form nor add `${GROK_PLUGIN_ROOT:-…}`
  as a second vector.
- NG3 **A new `AGENTS.rules.md` rule.** `cq-agents-md-tier-gate` classifies this as
  domain-scoped (single-file trigger: a SKILL.md edit) → the obligation belongs in the
  owning skills.
- NG4 **A single convergent rule bullet** across the skill-authoring skills. ADR-224 §1
  forbids an unqualified cross-harness rule; any bullet must be harness-qualified per skill.
- NG5 A runtime abstraction layer. `plugins/soleur/lib/harness.ts` already is the adapter.
- NG6 Rewriting the 34 unmarked skills' logic — only their invocation surface, and only
  where they are in the derived population.

## Functional Requirements

Re-based on plan v3 (the allowlist predicate; v1 marker census and v2 token blocklist are
refuted record in the plan). ADR-226 records the decision.

- **FR1 Predicate.** Every token in a population doc that names a known skill, command or
  agent is the canonical `soleur:<name>` at a prose boundary, a bare **skill** name in prose,
  or a path component; every token naming a known agent is the registry id at a prose
  boundary or a path component. Anything else is NONCANONICAL. Rules R1–R9, the boundary
  allowlist, the path class, the token class and the trailing-glue strip are constants in
  `plugins/soleur/lib/harness-parity.ts`, each with its rationale beside it.
- **FR2 Index derived, never listed.** Skill directories and command basenames via
  `git ls-files` with `:(glob)` magic; agents via `discoverAgentPaths()` → `pathToAgentId`
  (67; `README*` and `references/` excluded, as the Grok compat stubs are). `INDEX_GLOBS` and
  `POPULATION_GLOBS` are separate constants.
- **FR3 Population derived.** `:(glob)plugins/soleur/{skills,codex/skills,devin/skills}/*/SKILL.md`
  and `:(glob)plugins/soleur/commands/*.md` (106 docs on 2026-09-18), each glob carrying its
  region policy; `commands/help.md` excluded by path with the reason stated.
- **FR4 One exempt region kind.** `<!-- harness-forms:start|end -->`, honoured only under the
  `command` policy, strict marker grammar (case, CRLF and inline text are RED "malformed
  marker"; stray end, double start and unterminated start are RED); markers with any other
  name are transparent content. Fenced code is classified like prose; frontmatter is not exempt.
- **FR5 Born blocking, no baseline.** `harness-parity-tree.test.ts` asserts
  `expect(noncanonical).toEqual([])` per doc with the per-site message
  (`path:line: <site> — <harness>; write <canonical id>`), reports UNKNOWN-NS, and fails on
  `0 docs examined` and on any index-invariant breach (`|AGENTS| === EXPECTED_SOLEUR_AGENT_COUNT`,
  leaves unique and disjoint from skill names, every skill dir and command file present in
  `CANONICAL_IDS`).
- **FR6 Fixture self-test.** `harness-parity.test.ts` runs the classifier over synthesized
  fixtures under `test/fixtures/harness-parity/{skills,commands}/` (the directory selects the
  policy through the lib's own path→policy mapping) and pins every rule, both allowlists, the
  token class, the strip, the grammar, `fixDoc` idempotence and the empty-population throw;
  it also asserts the tree file carries the `toEqual([])` literal (cross-file sentinel).
- **FR7 `--fix`.** `plugins/soleur/scripts/harness-parity-census.ts --report | --fix`; `--fix`
  inverts only `/soleur:x`, `$soleur:x`, `@agent-soleur:x` and grok `/x` for a known skill,
  never a bare leaf, a hyphen mention, an honoured region or `$x`; idempotent.
- **FR8 Remediation.** The 1029 pre-remediation sites (62 docs) are canonical after this PR:
  `--fix` for the mechanical shapes, hand edits for bare leaves (registry ids), `@agent-<leaf>`,
  the grok stem, the two false positives (`"${work}"`, the rclone glob), the three go.md
  regions, go.md's bare-repo guard line, and the two `description:` substitutions.
- **FR9 Emit-time rendering.** Operator-pasted prompts a skill emits stay canonical in the doc
  and carry the sentence *render the entry as the active harness's operator-typed form per
  `formatSkillInvocation` before printing* (brainstorm, plan, work resume blocks;
  product-roadmap `next`; gdpr-gate's manual dispatch).
- **FR10 Adapter strings render per harness.** `pipelineInvocationSuffix(skill, harness)` and
  the harness-agnostic lines of `workflowFidelityInstructions` go through `formatSkillRef`;
  `invokeSkill("ship")` on Codex names `$soleur:postmerge` and not `/postmerge`.
- **FR11 Preambles carry the general rule.** The 12 `grok-harness-invoke` carriers state
  *any `soleur:<name>` in this document names a skill — on Grok Build, Read
  `plugins/soleur/skills/<name>/SKILL.md` in this process*; Guard 1 pins it.
- **FR12 Authoring surfaces.** The same bullet in `skill-creator` §Sharp Edges,
  `compound-capture` Step 8 (with Step 8.1's skill row as `soleur:foo`) and `heal-skill`'s
  change step; `AGENTS.rules.md`'s slash-form examples canonicalised (`/loop`, a Claude
  built-in, stays).

## Technical Requirements

- **TR1** Host: `plugins/soleur/test/harness-parity.test.ts` and
  `plugins/soleur/test/harness-parity-tree.test.ts`, auto-run by `bun test plugins/soleur/test/`
  (`lefthook.yml` `plugin-component-test` on any staged `plugins/soleur/**/*.md`; `scripts/test-all.sh`
  in CI's `test-bun` shard). No registration edit.
- **TR2** Whole-tree census; no diff scoping, no committed baseline, no per-doc vector.
- **TR3** `git ls-files` runs from `REPO_ROOT` derived from `PLUGIN_ROOT` with `--full-name`, so
  `cd plugins/soleur && bun test` resolves the same population.
- **TR4** Harness attribution in the message is a local lookup over (rule, preceding
  character) and never a verdict input; `unrecognised sigil` is the catch-all.
- **TR5** No `SUPPORTED_HARNESSES`, no `as const`/`never` re-derivation, no `tsc` gate — the
  attribution table cannot blind the gate, so it needs no exhaustiveness proof.
- **TR6** Guard 3 mutation matrix (plan v3): fixture-backed rows N5–N8 (incl. N5b–N5g) and
  the H rows run on every CI pass; N1–N4, N9–N13 are hand-run against a pristine copy and
  recorded in the PR body.
- **TR7** No `${CLAUDE_PLUGIN_ROOT:-…}`/`${GROK_PLUGIN_ROOT:-…}` form introduced.
- **TR8** No C4 edit; `c4-count-parity.test.sh` unchanged. ADR-226's ordinal is re-derived
  across every `origin/*` ref before merge.

## Acceptance Criteria

Plan v3 AC1–AC17 are the contract; the load-bearing ones restated:

- [x] AC1 The pre-remediation census is the RECORD in `census-baseline.md`, not a figure to
      re-derive: `1029 non-canonical sites in 62 docs` (bare-leaf 488 / grok 339 / claude-devin
      187 / claude-agent 8 / claude-leaf 3 / codex 2 / grok-stem 1 / unrecognised 1), 20
      UNKNOWN-NS, measured against base `f5ad46390`. Re-running it against a LATER `origin/main`
      does not reproduce that number and is not expected to — main advances under it (measured
      2026-09-18: 1028 / 62 / claude-devin 186, one site of drift). An earlier revision of this
      AC asked for re-derivation, which made it unsatisfiable by construction the moment a
      sibling PR merged.
- [ ] AC2 Post-remediation `--report` prints 0 sites; UNKNOWN-NS multiset (path, token) diffs
      empty against AC1 apart from the plan-prescribed `soleur:<name>` metavariables; `--fix`
      changes nothing.
- [ ] AC3 The `--fix` commit is reproducible from its parent.
- [ ] AC4 Fixture suite ≥ 30 tests, every fixture asserts verdict and message; both suites GREEN.
- [ ] AC5 N1–N13 and H1–H5 observed as stated; recorded in the PR body and in
      `guard3-mutation-matrix.txt`.
- [x] AC6 Independent spot-check greps: go.md's 8 hits all sit inside the three `harness-forms`
      regions (lines 130-157, 191-195, 211-213); `help.md` is excluded by path; the 5 skill hits are
      the prose compounds `/work-time` and `/work-start`, which the classifier reports as no
      reference. `Task [a-z-]+\(` returns 2, both `Task general-purpose(` — a Claude built-in agent
      type, not a Soleur registry leaf. The AC's literal greps are broader than the property; each
      hit is dispositioned here rather than the grep being narrowed.
- [x] AC9 No `${CLAUDE_PLUGIN_ROOT:-…}` / `${GROK_PLUGIN_ROOT:-…}` form INTRODUCED (TR7). The
      added-line grep returns 4; each `+` has a matching `-` — pre-existing lines this PR edited for
      a reference rewrite. Net new instances: 0.
- [ ] AC7/AC8 `components.test.ts` (budget 2442), `devin-cloud-mode.test.ts` (67),
      `workflow-fidelity.test.ts` GREEN.
- [ ] AC10–AC12 authoring bullets, emit-time sentences and preambles present as specified.
- [ ] AC13 ADR-226 exists; ordinal unique across `origin/*` at merge.
- [ ] AC14 `lint-agents-rule-budget.py` `[OK]` after the AGENTS.rules.md substitutions.
- [ ] AC15 `SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh` GREEN.
- [ ] AC16/AC17 PR body refs; spec and tasks re-based on v3.

## Risks

| Risk | Mitigation |
| --- | --- |
| Requiring Codex REDs all 12 currently-qualified skills | Sequence the canonical marker-block edit *with* the gate; it is one edit propagated across 64 byte-identical copies |
| Trigger regex misses a real invocation shape | TR6 mutation test + TR7 decoy; Open Question 2 |
| Block inserted inside the cloud-mode block breaks byte-identity for 24 skills | FR9 — anchor strictly after `soleur-cloud-mode:end` |
| Deriving `Harness` from the new array drops `"unknown"` and breaks `detectHarness` | Keep `\| "unknown"`; the 5-member union stays type-identical for all 3 importers |
| Ledger degrades into a rubber stamp | FR5 — mandatory dated, issue-linked, falsifiable reason; no bare "temporary" |
