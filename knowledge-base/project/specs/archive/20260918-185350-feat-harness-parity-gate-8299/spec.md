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

Re-based on plan v3. The v1/v2 goals this replaces described a marker census and a token
blocklist, both refuted (ADR-226 §Considered Options); they are recorded there, not here.

- G1 A born-blocking gate over a DERIVED population — every tracked `skills/*/SKILL.md`,
  `commands/*.md` and codex/devin wrapper, minus a stated per-path exclusion list.
- G2 Every token naming a known component resolves to one of six verdicts
  (`CANONICAL | BARE | PATH | NONCANONICAL | UNKNOWN-NS | EXEMPT`). NONCANONICAL must be 0.
- G3 No hand-listed member set decides anything: the index is `git ls-files` plus
  `discoverAgentPaths()`, and the population is `:(glob)` pathspecs (ADR-193 §5 applied to
  both). **Not carried from v2:** replacing `devin-cloud-mode.test.ts`'s `UNION` array was a
  v2 goal and is out of scope here — that file is untouched by this PR.
- G4 **No floors and no baseline.** The property is absolute, so a qualified-count floor and
  an auto-exempt ceiling (the v2 design) would be a compensation surface; ADR-226 rejects
  them as Option D. Anti-vacuity comes from permanent fixtures, an index invariant, a
  population invariant and a cross-file sentinel instead.
- G5 **No exemption ledger.** Exemptions reduce to one region kind (commands only, strict
  grammar) and four path exclusions, each carrying its reason in the constant itself.

## Non-Goals

- NG-M Bare mechanism nouns (`Skill tool`, `Task tool`, `subagent_type`) carrying no name
  through a sigil — **#8318**.
- NG-P Other agent-read docs: agent bodies (289 sites / 68 docs) and
  `skills/*/references/**` (84 / 19), measured 2026-09-18 — **#8317** (P1). Not "one glob
  line each"; see ADR-226 §Consequences for the four edits it needs.
- NG-U Gating `soleur:<unknown>` (R3). Reported and diffed, never failed — a typo is a
  different defect.
- NG1 **Mirror completeness** for the hand-ported trees (`.openhands/`, `.gemini/`) — **#8306**.
- NG2 **Migrating the `${CLAUDE_PLUGIN_ROOT:-…}` sites.** Owned by ADR-179 and open **#7453**.
  This work must not bless a `:-` form nor add `${GROK_PLUGIN_ROOT:-…}` as a second vector.
- NG3 **A new `AGENTS.rules.md` rule.** `cq-agents-md-tier-gate` classifies this as
  domain-scoped, so the obligation belongs in the owning skills. W11 edits EXAMPLES inside
  existing rule bodies; it adds no rule.
- NG5 A runtime abstraction layer. `plugins/soleur/lib/harness.ts` already is the adapter.

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
- [x] AC15 **AMENDED — CI's required `test` context is the gate, not a local battery.** The
      original AC asked for a local `SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh`. Per
      ADR-183 no local run is the merge gate: CI's required `test` context runs the same three
      shards on the PR head, and 25 further required contexts (`rule-body-lint`, `adr-ordinals`,
      `markdown-lint`, `grok-fidelity`, `skill-security-scan`, …) gate this diff. The one shard
      CI does not cover is `apps/web-platform/infra/`, and this diff touches it in **0** files
      (`git diff --name-only origin/main...HEAD | grep -c apps/web-platform/infra/`). Discharged
      locally instead: `bun test plugins/soleur/test/` 3046/0, the eval-harness round-trip suite,
      lefthook's full lint set, and the Guard 3 matrix. The queued local battery was killed
      (rc 143 = SIGTERM, a reap and not a verdict — it is recorded as neither green nor red).
      Amended explicitly rather than satisfied by a looser variant.
- [ ] AC16/AC17 PR body refs; spec and tasks re-based on v3.

## Risks

Re-based on plan v3; the v1/v2 rows referenced a trigger regex, a `Harness` re-derivation and
an exemption ledger, none of which this design contains.

| Risk | Mitigation |
| --- | --- |
| A BOUNDARY member is a harness sigil somewhere | None of the four adapters uses one (every `formatSkillInvocation` branch read). 18 of 23 members are measured load-bearing on the tree; 5 are stated as anticipated. ADR-226 makes re-reading the set an obligation when a fifth harness lands |
| `--fix` destroys a real byte | Measured, and it did: four sites, including a live `cp` glob. A slash after a span-CLOSING delimiter is now classified PATH (`closesSpan`), so no site is reported and nothing is rewritten; the residual post-condition refuses any rewrite that would not re-classify CANONICAL; `--fix` refuses a dirty tree so every rewrite is reviewable and revertible; and it skips docs with malformed markers. Two fixtures pin both directions, four mutations killed |
| A doc whose SUBJECT is the typed form gets canonicalised into falsehood | Happened to `skills/{go,help,sync}` and was caught at review. Those three plus `commands/help.md` are excluded by path, each with its reason in the constant, and the exclusion count is pinned |
| The gate's own population is silently narrowed | A population invariant counted from the tree test's own literal pathspecs, plus pins on the exempt surface and the exclusion map. Four narrowings mutation-proven RED |
| 483 leaf → id rewrites change sentence shape | Leaf→id is a function (uniqueness asserted); reviewed per doc group. Four sites where the bare word was not a component reference were found and hand-corrected |
| Emit-time rendering is forgotten at a new operator-facing site | AC11 greps the template shape; the `operator-typed-render` block states the obligation in all 10 affected docs; `formatSkillInvocation` now returns a typeable form on every harness |
| ADR ordinal moves | Re-derived across every `origin/*` ref; AC13 re-runs it immediately before merge |
| Region markers moved in go.md launder a dispatch | Review-only, one file, markers in the diff — stated as the honest limit in ADR-226 |
