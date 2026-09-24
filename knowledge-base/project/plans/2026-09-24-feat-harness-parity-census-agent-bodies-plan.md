---
title: "feat(harness): widen the harness-parity census to agent bodies (#8317 agent half)"
date: 2026-09-24
slug: feat-harness-parity-census-agent-bodies
branch: feat-one-shot-8317-agent-bodies-parity-census
issue: 8317
closes: 8317
type: feat
priority: p1-high
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat(harness): widen the harness-parity census to agent bodies

## Overview

The spec has no valid `lane:`, so this plan defaults to `cross-domain` (TR2 fail-closed).

The harness-parity census (ADR-226) checks that every component reference in agent-read plugin docs uses the canonical `soleur:<name>` / registry-id form. PR #8570 added the skill `references/**` population, which was one of the two populations #8317 deferred. This plan covers the other one, the 67 registry agent files under `plugins/soleur/agents/`. It also decides whether #8622 (the census rewriting quoted harness forms) is folded in here.

## Research Insights

### Premise Validation (Phase 0.6)

- **#8317**: OPEN. Its references half shipped in PR #8570 (MERGED 2026-09-24T02:26Z; ADR-245). The agent-body half is still open. The lib's own header comment agrees: `plugins/soleur/lib/harness-parity.ts` above `POPULATION_GLOBS` ("NG-P widening (#8317) is HALF DONE"). The premise holds.
- **#8622**: OPEN, labels `deferred-scope-out`, `meta/machinery`, `priority/p2-medium`. Its body describes the problem as contested-design. The premise holds. The disposition is under Decisions, D6.
- **The issue's site counts are stale.** #8317 quotes "35 sites / 15 docs", which is the #8299 plan's pre-R6b figure. ADR-226 §Consequences, in the NG-P bullet, already corrected this to **289 / 68**. Re-measured today with the live classifier (scratch script calling `readPopulation`, `census` and `formatReport` from `plugins/soleur/lib/harness-parity.ts` over `:(glob)plugins/soleur/agents/**/*.md`):
  - **Registry agents: 287 sites in 67 of 67 docs.** By shape: `bare-agent-leaf` 252, `sigil-skill` (grok `/plan`) 25, `ns-sigil` (`/soleur:x`) 10. By location: frontmatter `name:` 67 (every one a self-reference; 0 name another agent), frontmatter `description:` 92 in 50 docs, body 128.
  - **The agent references doc** (`plugins/soleur/agents/operations/references/service-deep-links.md`): 2 sites, both the bare leaf `service-automator`. 287 + 2 = 289, which matches the ADR.
  - **Code spans:** 38 sites in inline code and 1 in a fenced block. Each was read by hand: **none is an evidentiary quotation**. All 39 are ordinary references (`/plan`, `/soleur:architecture`, `` `security-sentinel` ``) and should be canonicalized.
  - The ADR's "69 `name:` lines across the 67 registry agents" is correct. The two extra lines are `name: <original-name>` template lines in `engineering/discovery/{agent-finder,functional-discovery}.md`. `<original-name>` is not an index member, so they classify as nothing.
- **`model.c4:118` "65 domain agents"** has moved. It is now `knowledge-base/engineering/architecture/diagrams/model.c4:142` (`description "65 domain agents across 8 departments"`), and the same string appears 4 times in `model.likec4.json`. The registry count is 67 (`EXPECTED_SOLEUR_AGENT_COUNT` in `plugins/soleur/lib/agent-registry.ts`). No `c4-count-parity.test.sh` row covers it (rows C1–C7 are all Sentry/Resend counts). The scheduled diagram-sync issues #8410 (item 2) and #8409 (item 2) report the same drift.
- **Codex/Devin `INSTRUCTIONS.md`**: neither file is in any `POPULATION_GLOBS` entry, and neither is matched by the globs this plan adds. ADR-226 §Decision 4 already classifies them as human-read ("the harness INSTRUCTIONS files are read by a person who types the form"). #8317's condition ("when the population widens past agent-read docs") therefore does not fire. No region and no exclusion is needed. This is recorded as a non-change (NG-2) rather than done silently.

### Property List (Phase 0.6b)

- **P1**: every agent-read doc under `plugins/soleur/agents/` is examined by the blocking census. After D2 that is exactly the 67 registry agents, because the one references doc is inlined into its consumer.
- **P2**: every component reference in those docs uses the canonical form (`soleur:<skill>` or a registry agent id), so it resolves on all four harnesses.
- **P3**: each agent's own frontmatter `name:` stays the bare leaf. `discoverAgentEntries` reads it into `agents.manifest.json`, and both Claude's loader and the Grok stub generator depend on it. The census must still not go green by exempting anything wider than that one value.
- **P4**: the architecture model's agent count equals the registry, and it stays equal (gated).
- **P5**: a later author reading the ADR and the authoring checklist is told the rule that the gate enforces.

### Cut List (Phase 0.6b)

- *"Codex/Devin INSTRUCTIONS.md need a harness-forms region or by-path exclusion"* → buys nothing for P1–P5. Neither file enters the widened population, and ADR-226 §4 already classifies them as human-read. **Cut.**
- *"#8622 option 3: `--fix` refuses to rewrite inside a code span"* → the property it buys is "a quoted harness form is not silently lost". In this population that property is already free: 0 of the 39 code-span sites are quotations, and `--fix` requires a clean tree, so every rewrite is reviewable in `git diff`. **Cut from this PR.** It remains on #8622 (D6).
- *A new `harness-forms`-style marker for agents* → no agent doc quotes a harness form as its subject. **Cut.**

### Relevant files

- `plugins/soleur/lib/harness-parity.ts`: `POPULATION_GLOBS`, `REFERENCES_PATHSPEC`, `regionPolicyForPath` (the nested-`SKILL.md` carve-out), `readPopulation` (the `?? g.regionPolicy` fallback), `classifyDoc` (the single verdict site), `fixDoc` (never rewrites bare leaves), the `Verdict` / `RegionPolicy` unions, `VERDICTS`, `formatReport`.
- `plugins/soleur/lib/agent-registry.ts`: `discoverAgentPaths` (inline README/`references/` filter), `pathToAgentId`, `discoverAgentEntries` (reads `name:` into the manifest), `EXPECTED_SOLEUR_AGENT_COUNT = 67`.
- `plugins/soleur/test/harness-parity-tree.test.ts`: literal `OWN_*` pathspecs, the admission proof ("the population is exactly the tracked doc set…"), the bounded-EXEMPT test (`totals.EXEMPT === 21`, `EXCLUDED_BY_PATH.size === 4`), per-doc dispatch.
- `plugins/soleur/test/harness-parity.test.ts`: `fixture(dir: "skills" | "commands", …)`, the `regionPolicyForPath` plumbing test (currently pins `plugins/soleur/agents/product/cpo.md` → `undefined`, which this PR flips), `frontmatter.md: frontmatter is not exempt`, the H5 violating-fixture list, and the no-orphan-fixture test.
- `plugins/soleur/test/lib/population-floors.ts`: `MIN_REGISTRY_AGENTS = 65` already exists.
- `plugins/soleur/scripts/sync-grok-agent-compat.ts`: regenerates `plugins/soleur/.claude-plugin/agents.manifest.json` and `.grok/agents/*.md` (descriptions go through `yamlQuote`). Drift is gated by `plugins/soleur/test/grok-agent-discoverability.test.ts` ("buildAgentsManifest matches committed manifest") and by `--check`.
- `plugins/soleur/docs/_data/agents.js` `extractSummary(body)`: the docs-site agent card is the first body line, not the frontmatter description. Five research agents' first line is the `> **Model override (haiku)**` blockquote, which contains `/plan`, `/brainstorm` and `/deepen-plan`.
- `plugins/soleur/test/c4-count-parity.test.sh`: the row table `id|edge|clause|mode|fn|derivation`, with exactly-one clause cardinality, `|| true` on every grep. `scripts/regenerate-c4-model.sh` (pinned `likec4@1.50.0`) regenerates `model.likec4.json`, which `plugins/soleur/test/c4-model-freshness.test.sh` byte-diffs.
- `plugins/soleur/AGENTS.md` §Agent Compliance Checklist: "Use [sibling] for [X]" (this is the authoring guidance that produced the 92 description sites) and §Adding a New Domain Leader step 4.
- ADR-226 (`knowledge-base/engineering/architecture/decisions/ADR-226-canonical-component-references-in-plugin-docs.md`): §Decision 2 (population sentence), §3 (one exempt region kind, commands only), §4 (human-read surfaces), §Consequences NG-P bullet.

### Institutional learnings applied

- `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`: validate each mechanism against the **post-remediation** tree. In particular, check that the remediation's own text does not match the classifier. The rewritten descriptions introduce `soleur:…` ids into frontmatter, and the carve-out must not start matching them. This is Guard 2 row M2.8.
- `2026-09-23-non-required-did-not-mean-decoupled-and-my-canonicalizer-rewrote-its-own-evidence.md` (#8570): `--fix` rewrote evidence in the widening PR's own commit. Mitigated here by measurement (0/39 code-span sites are quotations) and by reviewing the `--fix` diff site by site (Phase 3.2).
- `workflow-patterns/2026-07-17-grok-spawn-subagent-filename-stem-not-colon-name.md`: Grok spawns by stub filename stem. Stub `name:` is generated as the hyphen stem, independent of the agent's `name:`. The carve-out does not change this.
- `workflow-patterns/2026-07-11-grok-agent-compat-yaml-quoting.md`: an unquoted `:` in a description silently drops a stub. Every agent `description:` is already double-quoted, and `yamlQuote` re-quotes it for stubs. The rewrite adds many colons, so `grok inspect` is re-run (Phase 4).
- `2026-08-03-my-guards-error-channel-was-published-before-its-writers-ran.md`: new `c4-count-parity` derivations carry `|| true` on every grep.

### Conventions

- `cq-test-fixtures-synthesized-only`: new agent fixtures are synthesized. None is copied from a live agent.
- `hr-type-widening-cross-consumer-grep`: consumers of `Verdict` / `RegionPolicy` / `POPULATION_GLOBS` / `regionPolicyForPath` are only `plugins/soleur/lib/harness-parity.ts`, the two harness-parity test files and `plugins/soleur/scripts/harness-parity-census.ts` (verified with `git grep`).
- `cq-assert-anchor-not-bare-token`: the c4 rows are clause-anchored (`[0-9]+ domain agents across`), never a bare numeral.

### Related issues

- #8409 / #8410 (scheduled diagram sync): item 2 is the same `65 → 67` drift. This PR fixes that item and references both issues, but does not close them because they carry other items.
- #8318 (NG-M): a sibling census class. Untouched.
- #8307 (extract the population/floor/exemption triple): p3, related shape, not folded.
- #8622: disposition in D6.

### Functional overlap

`soleur:engineering:discovery:functional-discovery` searched 3 registries and found no overlap: no community tool lints cross-harness component references. Nothing was installed.

## Research Reconciliation: Issue vs. Codebase

| Issue / ADR claim | Reality (measured 2026-09-24) | Plan response |
|---|---|---|
| "35 non-canonical sites / 15 docs" in agents (#8317 table) | 287 sites / 67 docs in registry agents, plus 2 / 1 in the agent references doc. ADR-226 had already corrected the figure to 289 / 68 | Size from 287 + 2. Of these, 67 are carved out, 35 are mechanical (`--fix`) and 185 are hand edits (D4) |
| Glob excluding `README*` and `/references/` "to match `discoverAgentPaths()`" | The only non-registry `.md` under `agents/` is `operations/references/service-deep-links.md`. Claude Code's recursive `agents/**` loader does **not** apply that exclusion: the file loads as a phantom subagent `soleur:operations:references:service-deep-links`, and the docs site renders it as an agent card. That is why README says 68 agents while the registry says 67 (#8410 item 2 note) | Remove the non-member rather than encode an exclusion (D2). The population glob then equals the registry, and the gate asserts that `agents/` holds nothing else |
| "`model.c4:118` says 65 domain agents" | `model.c4:142`, plus 4 occurrences in `model.likec4.json` | Fix it at `:142`, regenerate the JSON, and register row C8 |
| "Codex/Devin INSTRUCTIONS.md need a harness-forms region or by-path exclusion" | Not in the population, and not matched by the new glob. ADR-226 §4 already classifies them as human-read | No change (NG-2) |
| Lib comment: "69 `name:` lines" | 67 frontmatter self-names, plus 2 body template lines `name: <original-name>` that classify as nothing | The carve-out targets the 67. The template lines sit in a body fenced block and are not index members, so they stay inert without a fixture |

## Decisions

- **D1: new `RegionPolicy` value `"agent"` and new `Verdict` `"SELF-NAME"`.**
  - **Scope.** The agent glob carries `"agent"`, so the carve-out's scope is structural. It is set by which glob matched, the same way `"command"` scopes `harness-forms`. `"agent"` does **not** honour `harness-forms`: only `"command"` does.
  - **Why a new verdict.** The self-name token gets its own verdict instead of reusing `EXEMPT`, because `EXEMPT` means "inside an honoured region" and its surface is pinned at exactly 21 sites in one file. Reusing `BARE` would mix the carve-out into skill-name counts. Skipping the token entirely would lose the per-doc anchor, "exactly one SELF-NAME per agent". That anchor is what goes RED when an agent's `name:` is rewritten, quoted or missing.
  - **Who agreed.** CTO, simplicity and architecture concurred. DHH preferred skipping the token; the rest of the panel outvoted him.
  - **Widening is contained.** The union's consumers are `harness-parity.ts` (`VERDICTS`, `classifyDoc`, `formatReport`), the two harness-parity test files and the census CLI (checked with `git grep`).
- **D2: fold in the phantom-agent removal.** Inline `service-deep-links.md` into `agents/operations/service-automator.md` and delete the file.
  - **Consumers.** `service-automator.md` is the doc's only consumer: 3 relative links, and `git grep service-deep-links` finds nothing else.
  - **Why not an exclusion.** Keeping the file under `agents/` would need an exclusion predicate plus a separate references glob. It would also keep shipping a phantom Claude subagent and a docs-site agent card. Inlining makes `agents/` equal the registry, so the population is one exact glob with no admission predicate. `readPopulation`'s `?? g.regionPolicy` fallback stays as it is.
  - **Inline threshold.** `wg-defer-only-after-inline-triage` applies: the fix is a handful of prose edits plus the move.
  - **Rejected alternatives.** A skill's `references/`: no skill owns the file, so the coupling would be arbitrary. Keeping it with an exclusion: that encodes the phantom instead of fixing it.
  - **Cost.** About 5.2 KB more per `service-automator` spawn, a rare, guided-tier-only agent.
  - **Public count becomes 67.** It changes in the surfaces listed in 1.4 and matches the registry and `model.c4`. The CPO found this is not a messaging concern.
- **D3: carve-out grammar.** The rule applies under policy `"agent"` only.
  - **The candidate line** is the **first** line matching `^name:` inside a *closed* leading frontmatter block: line 1 is exactly `---`, and a later line is exactly `---`.
  - **The candidate must equal `name: <v>` byte for byte**, with no quotes, no trailing text and no CR. `<v>` must equal the doc's filename stem (`basename(path, ".md")`).
  - **When it passes,** the one token on that line gets `SELF-NAME`. Every other token keeps its normal verdict: the rest of the frontmatter, a second `name:` line, and any body line.
  - **When it fails,** its bare-leaf site stays NONCANONICAL but carries a **dedicated message**. The default `write <registry id>` advice would lead an author to canonicalize `name:`, which breaks the manifest and loops them (CTO DX-1, spec-flow P0). The message reads: `agent self-name must be exactly "name: <stem>" (unquoted, equal to the filename); do not write the registry id here`.
  - **Why "first `^name:`" and not "first exact match".** With `name: "cpo"` followed by `name: cpo`, a first-exact-match rule would certify the second line while a YAML reader keeps the first (Kieran P1-1, spec-flow P1-2).
  - **No self-certification.** The identity comes from the **path**, never from content, so a doc cannot certify itself. Filename stems are unique leaves (the tree test asserts "unique leaves").
- **D4: remediation split.**
  - **Mechanical (35 sites):** 10 `/soleur:x` and 25 `/plan`-style. They go through `harness-parity-census.ts --fix` on a clean tree, reviewed with `git diff`.
  - **Bare leaves (185 sites):** 90 in descriptions and 95 in bodies. Each census message already names the registry id. Apply them with a throwaway scratch script that is never committed (advisor consult). It applies each `bare-agent-leaf` site's `fix` hint, skips the exceptions below, and lands as **its own commit**, reviewed line by line with `git diff --word-diff`. Paste the script source into the PR body (CTO).
  - **`fixDoc` is unchanged.** A permanent bare-leaf rewrite would break non-references; for example `` `clo.md` `` would become `soleur:legal:clo.md`.
  - **Known non-references, reworded rather than rewritten:**
    - `semgrep-sast.md`: the output literal `"semgrep-sast: 0 findings across N files"` becomes `"Semgrep SAST: 0 findings across N files"`. `git grep` finds no parser of that string.
    - `legal/clo.md`: `` `clo.md` `` is a filename, so it becomes a path such as `` `agents/legal/clo.md` ``, which classifies PATH.
  - **Operator-typed lines** (spec-flow P2-9). `ux-design-lead.md` ("Run `/soleur:pencil-setup`") and `cto.md` (`/soleur:architecture`) name a command the operator types. They follow the skills' existing canonical-then-render convention (ADR-226 §4, 22 precedents in skills) and are listed in the PR body.
  - **Anything else** found in review is reworded the same way and listed in the PR body.
- **D5: descriptions are rewritten, not carved out.** ADR-226's `frontmatter.md` fixture pins "frontmatter is not exempt", and the description is the most-read routing surface. Word count is unchanged, and chars grow by about 1,684 over 21,117. The CPO accepted this. A description size budget is out of scope, filed as **#8692**.
- **D6: #8622 is NOT folded in. It goes to a sibling PR.**
  - **Same module, different code path.** This PR changes membership (`POPULATION_GLOBS` / `regionPolicyForPath`) and one rule in `classifyDoc`. #8622 is about `fixDoc`'s rewrite behaviour and about exempting a quoted form under a non-`command` policy.
  - **Why option 3 cannot close it.** #8622's acceptance criteria need the literal payloads restored in `plan-sharp-edges.md` and `prd-template.md`. Option 3 (refusing `--fix` in code spans) cannot deliver that alone, because the tree gate would still RED on the restored literal. Closing it needs an exemption mechanism (option 1 or 2) plus an ADR-226 §3 amendment, which is the contested design its label records.
  - **No instances here.** 0 of the 39 code-span sites in this population are quotations.
  - **One overlap.** #8622 option 1 ("a third region policy") would build on the `RegionPolicy` union this PR widens.
  - **Where it is recorded.** Both facts go in a comment on #8622, not in the ADR (simplicity).
- **D7: render agent ids for Grok at the adapter, for stub descriptions only.** This follows the architecture reviewer's P1, which narrows the CTO's R5.
  - **Why.** ADR-226's title says harness forms are "the adapter's to render". The `.grok/agents` stubs are adapter output. Once descriptions carry canonical ids, `sync-grok-agent-compat.ts` `compatStubMarkdown` maps each **registry agent id** in the description through `agentIdToGrokSubagentType` (colon to hyphen stem, the Grok spawn key). `agents.manifest.json` stays canonical.
  - **Scope.** Skill ids (`soleur:plan`) are left as they are: the Grok skill form is `/plan`, and Grok already resolves `soleur:<skill>` through the `grok-harness-invoke` preamble. This touches the generator this PR already runs, plus one test.
  - **Out of scope.** Rendering ids inside agent **bodies** on Grok (the stub body is a path pointer, so the agent reads the canonical body) stays with #8063, and a comment is posted there.

## Implementation Phases

### Phase 1: Remove the phantom agent (D2)

1.1. Inline `plugins/soleur/agents/operations/references/service-deep-links.md` into `plugins/soleur/agents/operations/service-automator.md` as a trailing `## Service Deep Links` section.

- Demote every service `##` heading to `###`, including the `## Service Name` heading inside the fenced "Adding New Services" template.
- Drop the doc's preamble ("Reference file for the service-automator agent…", "Separated from the agent prompt…").
- Reword self-references to the old file: "To add a new service to this file" and "After adding the service here" become "this section".
- Replace "No changes to the service-automator agent prompt…" with wording that names no leaf.
- Keep every URL, permission and guided step byte-identical (AC4 diffs them).

1.2. Rewrite the 3 links (`service-automator.md`, the three `[service-deep-links.md](./references/service-deep-links.md)` occurrences) as in-document references ("§Service Deep Links below").

1.3. `git rm` the references file. Update the comment on `discoverAgentPaths` in `plugins/soleur/lib/agent-registry.ts`: the README/`references/` filter is now a defensive guard with no members, and `agents/` holds only agent definitions (enforced by the tree test).

1.4. Live counts:

- Run `bash scripts/sync-readme-counts.sh`, then `--check`. Expected: `README.md` ×2 and `plugins/soleur/README.md` go from 68 to 67.
- Hand-edit `plugins/soleur/README.md` `### Operations (6)` to 5, if the script does not.
- Hand-edit `knowledge-base/engineering/architecture/nfr-register.md` ("65 domain agents" to 67).
- Hand-edit `knowledge-base/engineering/grok-onboarding.md` ("**68** Soleur agents" to 67).
- `reusable-release.yml` (`find plugins/soleur/agents -name "*.md"` → `NEXT_PUBLIC_AGENT_COUNT` → `apps/web-platform/components/connect-repo/ready-state.tsx`) will derive 67 at the next release without an edit. Note it in the PR body.
- Leave historical "68" mentions alone: dated ADRs, plans, `scripts/grok-fidelity-bootstrap.sh`, and the dated snapshot in `knowledge-base/product/competitive-intelligence.md`.

### Phase 2: Tests first (`cq-write-failing-tests-before`)

2.1. **Fixtures (synthesized, `cq-test-fixtures-synthesized-only`)** go under `plugins/soleur/test/fixtures/harness-parity/agents/<case>/cpo.md`. `cpo` is a real registry leaf, so every file uses that stem.

| Case dir | Content | Expected |
|---|---|---|
| `self-name` | `---` / `name: cpo` / `description: "Synthetic."` / `---` / body | 0 NONCANONICAL, 1 SELF-NAME (must-PASS) |
| `wrong-leaf` | `name: cto` | 1 NONCANONICAL carrying the **dedicated self-name message** (D3), not `write soleur:engineering:cto` |
| `second-name-line` | `name: cpo`, then a second `name: cpo` in the frontmatter | 1 SELF-NAME + 1 NONCANONICAL (the second) |
| `quoted-then-bare` | `name: "cpo"`, then `name: cpo` | 0 SELF-NAME, 2 NONCANONICAL, the first with the dedicated message (the first `^name:` line decides) |
| `in-body` | valid frontmatter, plus a body line `name: cpo` | 1 SELF-NAME + 1 NONCANONICAL (the body line) |
| `description` | valid `name: cpo`, plus `description: "Use cpo for X."` | 1 SELF-NAME + 1 NONCANONICAL (the description) |

Plus `skills/self-name-under-skill.md`: the same frontmatter under the `skill` policy gives 1 NONCANONICAL, because the carve-out is scoped by policy.

The remaining grammar shapes are **one table-driven test with inline strings**, needing no fixture files: `name: cpo # c`, `name:  cpo`, `name: cpo\r` (CRLF), no leading `---`, and no closing `---`. Inline strings keep the `\r` from being normalized by an editor or git (spec-flow P2-10). Each must give 0 SELF-NAME and 1 NONCANONICAL with the dedicated message. The classifier is called directly with `classifyDoc(text, index, "agent", "agents/x/cpo.md")`.

2.2. **`plugins/soleur/test/harness-parity.test.ts`**:

- `fixture()`: accept `dir: "skills" | "commands" | "agents"`. For agents, take `name` as `<case>/cpo.md`, derive the policy through `regionPolicyForPath("plugins/soleur/agents/product/cpo.md")` (never hand-assigned), and pass the display path `agents/<case>/cpo.md` to `classifyDoc`.
- One test per fixture row, asserting counts **and** the message text for the dedicated-message rows.
- Plumbing: flip `regionPolicyForPath("plugins/soleur/agents/product/cpo.md")` from `toBeUndefined()` to `toBe("agent")`. Add the depth-5 `plugins/soleur/agents/engineering/review/security-sentinel.md` → `"agent"` (exercises `**`) and the anchored-prefix negative `vendor/plugins/soleur/agents/legal/clo.md` → `undefined`.
- **fixDoc pin:** `fixDoc(selfNameFixtureText, index, "agent") === selfNameFixtureText`, byte-identical.
- **H5 loader:** for `agents`, walk recursively and keep **files only**. `readdirSync(…, {recursive: true})` also yields directory entries, which throw `EISDIR` (Kieran P1-2). Use policy `"agent"` and path `agents/<case>/cpo.md`. Add the RED agent fixtures to the expected red list.
- **No-orphan:** for each agent case directory on disk, assert that this file contains the literal `"<case>/cpo.md"`. The existing `split("/")` form would bind `name` to the case directory, and `self-name` is a substring of the other case names, so the check would be vacuous (Kieran P1-2).

2.3. **`plugins/soleur/test/harness-parity-tree.test.ts`**:

- Admission proof: add the literal `const OWN_AGENTS = ":(glob)plugins/soleur/agents/**/*.md"`. Add `lsFiles(OWN_AGENTS)` to `expected` and to `admitted`. Add `expect(lsFiles(OWN_AGENTS).length).toBe(EXPECTED_SOLEUR_AGENT_COUNT)` with a failure message: "every .md under agents/ loads as a Claude subagent; agent-owned reference text belongs in the agent body".
- New test, **"each agent doc carries exactly one self-name"**: for every doc whose path starts `plugins/soleur/agents/`, `counts["SELF-NAME"] === 1`. The message names the file and the rule (CTO DX-2), for example `<path>: 0 self-name — frontmatter must open on line 1 with --- and contain exactly "name: <stem>"`. This single assertion covers a non-agent `.md` dropped under `agents/` (0 self-names), a rewritten, quoted or missing `name:`, and a policy regression. It replaces the separate registry-purity, policy-resolution and manifest-agreement tests an earlier draft had (simplicity, DHH). The test also asserts that the number of agent docs it checked equals `EXPECTED_SOLEUR_AGENT_COUNT`, so a filter typo that matches nothing cannot pass vacuously.
- The bounded-EXEMPT test stays byte-identical (21 / go.md / 3 regions / `EXCLUDED_BY_PATH.size === 4`), which proves the carve-out did not use the exemption channel.

2.4. **`plugins/soleur/test/c4-count-parity.test.sh`**: add `derive_registry_agents()`, which is `{ git -C "$REPO_ROOT" ls-files -- ':(glob)plugins/soleur/agents/**/*.md' || true; } | wc -l | tr -d ' '`. Add the row `"C8|plugin.agents|[0-9]+ domain agents across|num|derive_registry_agents|git ls-files ':(glob)plugins/soleur/agents/**/*.md' | wc -l"`.

2.5. **Record RED per test.** Run `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/harness-parity-tree.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh`. Expected, before any lib change:

- Every agents fixture test REDs with `no population glob matched`. This is a harness RED, not a classifier RED; Phase 3a converts it.
- The tree admission proof REDs, because `docs.length` is short by 67.
- The "exactly one self-name" test is vacuously GREEN: no agent docs are in the population yet.
- C8 REDs: the prose says 65 and the derivation gives 67.

### Phase 3: Library change

3a. **Membership only.** In `plugins/soleur/lib/harness-parity.ts`:

- Widen `RegionPolicy` to `"skill" | "command" | "agent"` and `Verdict` with `"SELF-NAME"`, and add it to `VERDICTS`.
- Add the population entry `{ pathspec: ":(glob)plugins/soleur/agents/**/*.md", regionPolicy: "agent" }`.

Re-run and record the result. The agents fixtures now RED **on the classifier** (the `self-name` must-PASS row reports 1 NONCANONICAL). The tree reports 287 NONCANONICAL. The "exactly one self-name" test REDs on all 67 docs. This is the classifier-level RED the carve-out must turn green.

3b. **The carve-out** (D3), in `classifyDoc`, only when `regionPolicy === "agent"`:

- Before the token loop, find the leading frontmatter bounds and the first `^name:` line inside them.
- If that line is byte-exactly `name: ${basename(path, ".md")}`, mark it `selfNameLine`. The site on it whose token equals the stem gets `SELF-NAME`.
- Otherwise, a `bare-agent-leaf` site on the candidate line keeps NONCANONICAL with the dedicated D3 message.
- No other code path changes. `fixDoc` is untouched: it never rewrites `bare-agent-leaf`, and the 2.2 pin holds it.
- `formatReport` header: add `${totals["SELF-NAME"]} self-name`.
- Rewrite the header comment above `POPULATION_GLOBS` ("NG-P widening … HALF DONE") to say NG-P is complete and to name the carve-out. Update the `:14` header sentence that describes `discoverAgentPaths` exclusions.

Expected after 3b: the fixture suite is GREEN. The tree shows exactly 220 NONCANONICAL (287 − 67), and the self-name test is GREEN.

### Phase 4: Remediation

4.0. **Baseline.** Run `bun plugins/soleur/scripts/harness-parity-census.ts --report | awk '/^unknown-ns:/{f=1;next} /^[a-z]/{f=0} f' | sort > "$SCRATCH/unk-before.txt"` (spec-flow P1-5, Kieran P2-7).

4.1. Commit Phases 1–3 so the tree is clean, which `--fix` requires.

4.2. **Mechanical fixes.** Run `bun plugins/soleur/scripts/harness-parity-census.ts --fix`, then `git diff`. Read every hunk; about 35 rewrites are expected. Commit.

4.3. **Bare leaves.** Apply the 185 bare-leaf rewrites through the D4 scratch script, skipping the exceptions. Read `git diff --word-diff` line by line. Descriptions stay double-quoted YAML. Commit.

4.4. **Check.** `--report | head -3` shows `0 non-canonical sites` and `67 self-name`. Repeat the 4.0 command into `unk-after.txt`; `diff unk-before.txt unk-after.txt` must be empty (CPO 3).

### Phase 5: Derived artifacts and records

5.1. **Grok stubs (D7).** In `plugins/soleur/scripts/sync-grok-agent-compat.ts` `compatStubMarkdown`, map every registry agent id in the description through `agentIdToGrokSubagentType` before `yamlQuote`. Add a test to `plugins/soleur/test/grok-agent-discoverability.test.ts`: no committed `.grok/agents/*.md` description contains a `soleur:<registry agent id>` colon form, and the manifest `description` for the same agent does contain it. Then run the script, then `--check`. This regenerates `agents.manifest.json` and the stubs.

5.2. **Architecture model.** In `knowledge-base/engineering/architecture/diagrams/model.c4`, change `65 domain agents across 8 departments` to 67. Then run `bash scripts/regenerate-c4-model.sh` (pinned `likec4@1.50.0`) to regenerate `model.likec4.json`.

5.3. **Amend ADR-226** through `soleur:architecture`, using the dated `> **Amended 2026-09-24 (#8317)**` blockquote convention that ADR-245 used, not rewritten prose:

- §Decision 2 population: the agent glob and the `"agent"` policy.
- §Decision 2 index: the `README*`/`references/` filter is now defensive, with no members.
- A new clause after §3: the self-name carve-out (the D3 grammar, the `SELF-NAME` verdict, the per-doc anchor). It is **not** an exempt region, and frontmatter as a whole stays non-exempt.
- The `agents/`-only invariant (D2).
- D7: stub descriptions are rendered by the adapter.
- The fixture count in §6.
- The NG-P bullet marked discharged, with the historical measurement kept.

5.4. **`plugins/soleur/AGENTS.md`**:

- §Agent Compliance Checklist: change "Use [sibling] for [X]" to "Use [sibling's registry id, as printed in the census `write` hint] for [X]". A fixed `soleur:<domain>:<leaf>` template gives the wrong id for nested agents (CTO DX-3).
- §Directory Structure: add one line saying `agents/` holds only agent definitions, because Claude loads every `.md` under it as a subagent.

5.5. **Issue comments.** Comment on #8622 (D6 facts), #8063 (agent-body rendering, D7) and #8409/#8410 ("item 2 fixed by PR #…").

### Phase 6: Verification

6.1. Run the whole plugin battery, not a hand-picked list (spec-flow P1-6):

- `bun test plugins/soleur`.
- Every `plugins/soleur/test/*.test.sh`, including `c4-count-parity`, `c4-model-freshness`, `ticket-triage-clauses`, `ux-design-lead-*-guard`, `eval-gate`, and `agent-originality` (record the new top-pair score; `agent-finder` ↔ `functional-discovery` was about 41.7% against a 50% fail line).
- `bash scripts/lint-agents-enforcement-tags.test.sh`.
- `cd apps/web-platform && npx vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts`.

6.2. **Docs site.** Evaluate `plugins/soleur/docs/_data/agents.js`'s default export before and after the change, and diff the per-agent `description` summaries. Expected:

- 67 agents, and the `service-deep-links` card is gone.
- Every other change swaps an identifier token only, and none is empty or truncated.
- The five research-agent cards take their summary from the `> **Model override**` blockquote, so they will read `soleur:plan` where they read `/plan`. That card text already quotes a blockquote today, so this is accepted and recorded as a known exception, not fixed here.

6.3. **Grok discovery.** With grok on PATH, run `bun test plugins/soleur/test/grok-inspect-contract.test.ts plugins/soleur/test/grok-agent-discoverability.test.ts`. No `SKIP:` line may appear. The `grok inspect` arm counts at least 67 `soleur-*` agents, which proves the stubs still parse (CPO condition 5, deterministic half). Description content is covered by `sync-grok-agent-compat.ts --check` and the 5.1 test. Codex and Devin registration is covered by `harness-discovery-smoke` in CI. A live model spawn is not run: stub filenames, stub `name:` and manifest `name` are all unchanged.

## Files to Edit

- `plugins/soleur/lib/harness-parity.ts`: unions, `VERDICTS`, the agent glob, the `classifyDoc` self-name rule and message, `formatReport`, header comments.
- `plugins/soleur/lib/agent-registry.ts`: the `discoverAgentPaths` comment only.
- `plugins/soleur/scripts/sync-grok-agent-compat.ts`: map agent ids in stub descriptions (D7).
- `plugins/soleur/test/harness-parity.test.ts`: fixture helper, fixture tests, table-driven grammar test, plumbing, fixDoc pin, H5 loader, no-orphan.
- `plugins/soleur/test/harness-parity-tree.test.ts`: `OWN_AGENTS`, admission proof, per-doc self-name test.
- `plugins/soleur/test/grok-agent-discoverability.test.ts`: the stub-description test.
- `plugins/soleur/test/c4-count-parity.test.sh`: `derive_registry_agents`, row C8.
- `plugins/soleur/agents/**/*.md`: all 67 are remediated, 50 of them in their descriptions. `operations/service-automator.md` also receives the inlined section.
- Regenerated, not hand-edited: `plugins/soleur/.claude-plugin/agents.manifest.json` and `.grok/agents/soleur-*.md`.
- `knowledge-base/engineering/architecture/diagrams/model.c4`, plus `model.likec4.json` (regenerated).
- `knowledge-base/engineering/architecture/decisions/ADR-226-canonical-component-references-in-plugin-docs.md`.
- `knowledge-base/engineering/architecture/nfr-register.md` and `knowledge-base/engineering/grok-onboarding.md`: counts.
- `plugins/soleur/AGENTS.md`.
- `README.md` and `plugins/soleur/README.md`: counts, through `sync-readme-counts.sh` plus the Operations heading.

## Files to Create

- `plugins/soleur/test/fixtures/harness-parity/agents/{self-name,wrong-leaf,second-name-line,quoted-then-bare,in-body,description}/cpo.md`
- `plugins/soleur/test/fixtures/harness-parity/skills/self-name-under-skill.md`

## Files to Delete

- `plugins/soleur/agents/operations/references/service-deep-links.md`: its content moves into `service-automator.md`.

## Open Code-Review Overlap

None. I queried 76 open `code-review` issues against every path above and found 0 matches.

## Non-Goals

- **NG-1:** #8622, the quoting affordance and `--fix` refusal in code spans (D6). It stays open, with a comment.
- **NG-2:** Codex/Devin `INSTRUCTIONS.md`. ADR-226 §4 classifies them as human-read and they sit outside the population, so no region or exclusion is needed.
- **NG-3:** a size budget for agent descriptions. Filed as **#8692**.
- **NG-4:** Grok rendering of agent ids inside agent **bodies** (D7). That belongs to #8063.
- **NG-5:** historical "68 agents" mentions in dated ADRs, plans, `scripts/grok-fidelity-bootstrap.sh` and the competitive-intelligence snapshot. They are records, not live counts.
- **NG-6:** the unknown-ns backlog (341 entries, all outside agents). It is reported but not gated, per ADR-226.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Exempt the whole agent frontmatter | ADR-226's `frontmatter.md` pins "frontmatter is not exempt", and the 92 description sites are real routing references |
| Reuse `EXEMPT` for the self-name | Breaks the bounded-EXEMPT pin (21 sites, one file). EXEMPT means an honoured region |
| Skip the self-name token (no verdict) (DHH) | Loses the per-doc "exactly one" anchor, which is the check that catches a rewritten or quoted `name:` or a stray non-agent `.md` |
| A separate registry-purity set-identity test, a manifest-agreement test and a c4 row-id assertion (earlier draft) | Each repeated coverage that the per-doc self-name test, the admission-proof count or C8 already provides (simplicity, DHH). Cut |
| Delete the `discoverAgentPaths` README/`references/` filter (simplicity) | Widens registry semantics for every consumer (Grok stubs, manifest, harness spawn) to buy nothing. The per-doc self-name test already reds on a stray `.md`. The filter is kept as a defensive guard with an updated comment |
| Keep `service-deep-links.md` under a glob exclusion | Encodes the phantom Claude subagent instead of fixing it |
| Move `service-deep-links.md` under a skill's `references/` | No skill consumes it |
| Rewrite `name:` to the registry id | The manifest `name`, Claude's loader and harness lookups all key on the leaf |
| Add a permanent bare-leaf arm to `fixDoc` (advisor) | It would corrupt non-references (`clo.md` would become `soleur:legal:clo.md`). A one-shot scratch script plus review gets the same result |
| Fold in #8622 option 3 now | It cannot meet #8622's own acceptance criteria, and it protects 0 sites here (D6) |

## Open Questions

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a Soleur agent whose instructions a rewrite mangled, misbehaving when spawned on any of the four harnesses. The concrete risks: `semgrep-sast` emitting a changed findings line; `clo` pointing at a file that does not exist; `service-automator` losing its guided-tier deep links; a description routing to the wrong agent; Grok stub descriptions naming spawn keys that do not resolve. The worst case is an agent's own `name:` being rewritten, which makes it unroutable. The per-doc self-name test reds that case.
- **If this leaks, the user's data / workflow / money is exposed via:** nothing. No data path, credential or network surface is touched. The change covers plugin prose, a lint, a generator and generated manifests.
- **Brand-survival threshold:** `single-user incident`. Carried from #8317: agent bodies are read by every spawned subagent on every harness. `requires_cpo_signoff: true`. The CPO signed off at plan time with conditions (see Domain Review). `soleur:engineering:review:user-impact-reviewer` runs at review.

## Observability

Not required under the plan Phase 2.9 skip condition. No edited path sits under `apps/*/server/`, `apps/*/src/` or `apps/*/infra/`, and there is no new infrastructure. One edited script, `plugins/soleur/scripts/sync-grok-agent-compat.ts`, is a local generator with a `--check` drift mode already wired to CI, not a runtime surface. The deliverable is a CI gate. Its signal is the per-doc test names under the required `test` check, and `harness-parity-census.ts --report` run locally.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-226** through `soleur:architecture`, using dated amendment blockquotes and no new ordinal. The amendment covers:

- the §Decision 2 population and index sentences;
- the self-name clause after §3;
- the `agents/`-only invariant;
- D7 (adapter-rendered stub descriptions);
- the fixture count in §6;
- NG-P marked discharged.

This extends ADR-226, as ADR-245 did for the references half. The #8622 disposition goes in the issue, not the ADR.

### C4 views

**Container `platform.plugin.agents`:** `"65 domain agents across 8 departments"` becomes 67 in `model.c4`, `model.likec4.json` is regenerated, and the count is registered as row C8 in `plugins/soleur/test/c4-count-parity.test.sh`.

All three `.c4` files were checked:

- **External actors:** none added or changed.
- **External systems:** `grokBuild` and `devin` are already modeled, and their `-> plugin` edges are unchanged. This PR changes doc text and stub descriptions, not load paths.
- **Containers:** `agents` changes its count only. `skillloader -> agents "Discovers"` is still accurate.
- **Views:** `views.c4` already includes `platform.plugin.agents`.
- **Spec:** `spec.c4` kinds are unchanged.

The model never counted the phantom references doc: it says 65, not 68. `c4-count-parity.test.sh` must be green after the edit.

### Sequencing

Everything ships in this PR. There is no soak.

## Guard Contract

### Guard 1 — agent population is the registry

**Property.** The census examines every tracked `.md` under `plugins/soleur/agents/` under the `agent` policy. Every such doc is a registry agent, so no agent-read doc escapes the gate and no non-agent doc sits there to load as a phantom Claude subagent.

**Assembly.** The chokepoint is the `POPULATION_GLOBS` entry `:(glob)plugins/soleur/agents/**/*.md`. It feeds `readPopulation` (the git `ls-files` engine) and `regionPolicyForPath` → `globToRegex` (the regex engine).

- **Admission proof.** It counts from the tree test's own literal `OWN_AGENTS` pathspec and pins that count to `EXPECTED_SOLEUR_AGENT_COUNT`.
- **Per-doc self-name test.** It proves each admitted doc resolved to `"agent"` and is a real agent: a `"skill"` policy, or a doc with no frontmatter self-name, yields 0 self-names.
- **`EXCLUDED_BY_PATH`.** This is the one other place that can remove members. Its size is pinned at 4.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the agent entry from `POPULATION_GLOBS` | RED: admission proof (`docs.length` ≠ expected) |
| 2 | Narrow the entry to `:(glob)plugins/soleur/agents/*/*.md` | RED: admission proof (depth-4 and depth-5 agents dropped) |
| 3 | Dispatch: set the entry's `regionPolicy` to `"skill"` | RED: per-doc self-name (0 on all 67), plus 67 NONCANONICAL |
| 4 | Second member: add `plugins/soleur/agents/operations/references/x.md` or `agents/README.md` next to the 67 | RED: admission count 68 ≠ 67, plus per-doc self-name 0 for the stray |
| 5 | Add a real agent path to `EXCLUDED_BY_PATH` | RED: `EXCLUDED_BY_PATH.size === 4`, plus the admission proof |
| 6 | Regress `globToRegex`'s `**` handling | RED: fixture plumbing (depth-5 `security-sentinel.md` → undefined), plus the references depth test |
| H1 | Harness: the tree test's per-doc loop filters on `plugins/soleur/agents/` with a typo and matches nothing | RED: the existing "every examined doc was dispatched" test does not catch it, so the per-doc test also asserts that the number of agent docs it checked equals `EXPECTED_SOLEUR_AGENT_COUNT` |
| H2 | Harness, must-PASS non-canonical input: depth-5 `plugins/soleur/agents/engineering/review/security-sentinel.md` and depth-4 `plugins/soleur/agents/legal/clo.md` | PASS (`"agent"`) |

**Anchor.** `EXPECTED_SOLEUR_AGENT_COUNT` lives in `plugins/soleur/lib/agent-registry.ts`. It is independently pinned by the manifest `count` and the 67 `.grok/agents` stubs (`grok-agent-discoverability.test.ts`, `sync-grok-agent-compat.ts --check`). A same-size substitution (swap an agent for a non-agent) is caught by the per-doc self-name test, not by the count.

### Guard 2 — the self-name carve-out is exactly one token per agent

**Property.** In an `agent`-policy doc, the only bare agent leaf that escapes R6b is the one on the first `^name:` line inside a closed leading frontmatter, when that line is byte-exactly `name: <filename stem>`. Every other bare leaf stays NONCANONICAL, and a rejected self-name line says how to fix it without canonicalizing it.

**Assembly.** `classifyDoc` is the single verdict site. The carve-out is one line index, computed once per doc before the token loop and only under `regionPolicy === "agent"`.

- `fixDoc` never rewrites `bare-agent-leaf`, and is pinned byte-identical on the fixture.
- `census` only folds counts.

The anchor is the tree test's per-doc exactly-one assertion.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Identity keyed on "any registry leaf" instead of "own stem" | RED: `wrong-leaf` |
| 2 | Second member: the carve-out applied to every `name:` line | RED: `second-name-line` |
| 3 | "First exact match" instead of "first `^name:` line" | RED: `quoted-then-bare` |
| 4 | Scope: any line starting `name:` (not frontmatter-bound) | RED: `in-body`, plus the table rows "no leading `---`" and "no closing `---`" |
| 5 | Key scope: the carve-out widened to the whole frontmatter | RED: `description`, plus the tree (220 sites would vanish) |
| 6 | Policy scope: not gated on `"agent"` | RED: `skills/self-name-under-skill.md` |
| 7 | Grammar loosened (trim, regex search, quote-strip) | RED: the table rows (`# c`, double space, CRLF) and `quoted-then-bare` |
| 8 | Dispatch: `selfNameLine` never set | RED: the `self-name` must-PASS fixture, plus per-doc self-name on all 67 |
| 9 | Message regresses to `write <registry id>` on a rejected self-name line | RED: the message assertions on `wrong-leaf`, `quoted-then-bare` and the table rows |
| 10 | Live tree: `name:` in `cpo.md` rewritten to `soleur:product:cpo`, quoted, or removed | RED: per-doc "exactly one self-name" (0) |
| 11 | Post-remediation self-match: the carve-out also matches canonical ids that remediation wrote into descriptions | RED: per-doc count would be greater than 1 in 50 docs |
| H1 | Harness: `fixture()` hand-assigns `"skill"` to agent fixtures | RED: the `self-name` must-PASS row |
| H2 | Harness: the H5 loader omits `agents/`, or the no-orphan check reverts to `split("/")` | RED: the H5 red-list mismatch, plus the per-case literal no-orphan assertion |
| H3 | Harness, must-PASS permitted variant: `name:` as the third frontmatter key (the live tree has 67 instances; `description` precedes `name` in none, but the rule is key-order independent), checked by one inline table row | PASS |

**Anchor.** The per-doc `counts["SELF-NAME"] === 1` compares against a property of each live file, and its denominator is pinned to `EXPECTED_SOLEUR_AGENT_COUNT`, a constant outside `harness-parity.ts`. The bounded-EXEMPT pin is untouched.

### Guard 3 — model.c4 agent count parity (row C8)

**Property.** The count stated in the `platform.plugin.agents` description equals the number of tracked `.md` files under `plugins/soleur/agents/`. Guard 1 keeps that set equal to the registry.

**Assembly.** This is the `REGISTRY` row loop in `plugins/soleur/test/c4-count-parity.test.sh`:

- row `C8`;
- the clause `[0-9]+ domain agents across`, which must match exactly once;
- the derivation `derive_registry_agents` (`git ls-files … || true`).

`c4-model-freshness.test.sh` holds `model.likec4.json` in step with `model.c4`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the `model.c4` prose from `67` to `66` | RED: C8 mismatch |
| 2 | Add a 68th agent file without updating `model.c4` | RED: C8 mismatch, plus Guard 1 |
| 3 | Second member: duplicate the clause elsewhere in `model.c4` | RED: cardinality is 2, not 1 |
| 4 | The derivation points at a wrong path and returns 0 | RED: C8 mismatch (0 ≠ 67). The `\|\| true` makes the suite print the mismatch instead of aborting under `set -e` |
| H1 | Harness: delete the C8 row | Not caught by this suite. The same residual applies to C1–C7. Review sees the deletion in the diff (an explicit row-id assertion was proposed and cut: it would be deleted in the same diff) |
| H2 | Harness, must-PASS: different surrounding wording that keeps the clause (`67 domain agents across eight departments`) | PASS |

**Anchor.** The derivation reads the git tree, and the prose lives in a different file. To weaken the guard, a diff has to edit both.

## Acceptance Criteria

- [ ] **AC1** `bun plugins/soleur/scripts/harness-parity-census.ts --report | head -3`: the header shows `0 non-canonical sites`, `67 self-name`, `21 exempt` and `0 marker errors`, and the command exits 0.
- [ ] **AC2** The committed agents fixtures show the Phase 2.5 → 3a → 3b progression. They RED at 3a on the classifier and are GREEN after 3b. `bun test plugins/soleur/test/harness-parity.test.ts plugins/soleur/test/harness-parity-tree.test.ts` is green. The live-tree rows no fixture covers (Guard 1 rows 1, 3 and 4; Guard 2 row 10) were each executed once, observed RED, and reverted. The observed failing test names are listed in the PR body.
- [ ] **AC3** `git ls-files -- ':(glob)plugins/soleur/agents/**/*.md' | wc -l` prints `67`, and `plugins/soleur/agents/operations/references/` does not exist.
- [ ] **AC4** No deep-link content is lost. Take `git show origin/main:plugins/soleur/agents/operations/references/service-deep-links.md` from `## Cloudflare` onward, apply `sed 's/^## /### /'`, and diff it against the new `## Service Deep Links` section of `service-automator.md`. The diff contains only the reworded self-reference lines named in 1.1. `git grep -n service-deep-links -- plugins/soleur/agents plugins/soleur/docs` prints nothing.
- [ ] **AC5** `bash scripts/sync-readme-counts.sh --check` exits 0. `README.md` and `plugins/soleur/README.md` say 67 agents, and `### Operations (5)` appears. `nfr-register.md` and `grok-onboarding.md` say 67. No historical "68" was edited (NG-5).
- [ ] **AC6** `bun plugins/soleur/scripts/sync-grok-agent-compat.ts --check` exits 0, and `diff <(git show origin/main:plugins/soleur/.claude-plugin/agents.manifest.json | jq '[.agents[].name]') <(jq '[.agents[].name]' plugins/soleur/.claude-plugin/agents.manifest.json)` is empty.
- [ ] **AC7** `bash plugins/soleur/test/c4-count-parity.test.sh` prints `PASS: C8`, and `bash plugins/soleur/test/c4-model-freshness.test.sh` passes.
- [ ] **AC8** `diff "$SCRATCH/unk-before.txt" "$SCRATCH/unk-after.txt"` (Phase 4.0 and 4.4) is empty.
- [ ] **AC9** The 5.1 stub-description test is green: no `.grok/agents/*.md` description contains a colon-form registry agent id, and the manifest keeps them.
- [ ] **AC10** The docs-site agent data yields 67 agents. The before/after summary diff changes identifier tokens only, no summary is empty, and the `service-deep-links` card is gone. The research-agent blockquote exception is recorded.
- [ ] **AC11** `bun test plugins/soleur/test/grok-inspect-contract.test.ts plugins/soleur/test/grok-agent-discoverability.test.ts`, run with grok on PATH, passes and prints no `SKIP:`.
- [ ] **AC12** ADR-226 carries the dated amendment covering every item in 5.3. `plugins/soleur/AGENTS.md`'s checklist names siblings by registry id and states the `agents/`-only line.
- [ ] **AC13** The full Phase 6.1 battery is green.
- [ ] **AC14** The PR body:
  - contains `Closes #8317` and `Ref #8622` (not closes);
  - lists every D4 hand-reworded or operator-typed site and includes the scratch script source;
  - notes the `NEXT_PUBLIC_AGENT_COUNT` change;
  - records the comments posted on #8622, #8063, #8409 and #8410.

## Test Scenarios

1. The live tree after remediation: 0 NONCANONICAL, and exactly one SELF-NAME in each of the 67 agent docs.
2. Each Phase 2.1 fixture row and each table row classifies as stated, including the dedicated self-name message.
3. `fixDoc` on the `self-name` fixture is byte-identical.
4. `regionPolicyForPath` resolves depth-4 and depth-5 agents to `"agent"`, and an unanchored prefix to `undefined`.
5. A stray `.md` staged under `agents/` reds the admission count and the per-doc self-name test. This is a manual AC2 mutation and is not committed.
6. C8 fails on `66` and passes on `67`.
7. A regenerated Grok stub's description names `soleur-marketing-copywriter` where the manifest names `soleur:marketing:copywriter`.

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** The CTO agreed with the `"agent"` policy and the `SELF-NAME` verdict (a visible count is the design's main anchor), with keeping #8622 out, and with amending rather than creating an ADR. Each raised risk and its disposition:

- **R1** (`fixDoc` would rewrite `name:`): false as stated. `fixDoc`'s replacement arms exclude `bare-agent-leaf`. It is pinned anyway by the byte-identical fixture (2.2).
- **R2** (the phantom `service-deep-links` agent): folded in as D2.
- **R3 / R4** (a circular population proof, and FS vs git): the tree test uses literal pathspecs plus set identity with `discoverAgentPaths()`. D2 removes the need for any predicate or fallback change.
- **R5** (Grok colon ids): narrowed per the architecture review. Stub descriptions are adapter-rendered in this PR; agent-body rendering stays with #8063 (D7).
- **R6** (description cost): filed as #8692.
- **R7** (template `name:` lines): pinned inert by fixture.
- **R8** (`invocation-axis.test.ts`): added to verification.

### Product/UX Gate

**Tier:** none (no UI surface. The only user-visible outputs are agent routing text and a docs-site card and count derived from data. No file under `components/**`, `app/**/page.tsx` or `app/**/layout.tsx`.)
**Decision:** reviewed (CPO plan-time sign-off, required by the `single-user incident` threshold)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

**CPO: APPROVE WITH CONDITIONS.** Each condition is encoded:

1. Pin the reworded output literals. AC9: grep-verified that no consumer exists.
2. A test fails if an agent's `name:` stops being a bare leaf. Guard 2 row 10, plus the per-doc SELF-NAME assertion.
3. Every canonical reference resolves. AC8: the unknown-ns set diff.
4. Diff the docs-site cards. AC10.
5. Non-Claude harness check. AC11 (`grok inspect`) and Codex/Devin `harness-discovery-smoke` in CI. A live model spawn is declined; the reason is in Phase 6.3 and D7.
6. On the phantom removal:
   - (a) Deep links survive the inline: AC4.
   - (b) CI fails on a non-agent `.md` under `agents/`: Guard 1 row 4 (registry-purity), plus Guard 2's per-doc SELF-NAME for a frontmatter-less file.
   - (c) Only live counts change: AC5, NG-5.
   - (d) No docs link to the removed card: AC10.

The CPO found the public count moving from 68 to 67 is not a messaging concern (no positioning claim states 68), and that the description length cost is acceptable.

### Plan Review (5-agent eng panel + CTO devex; threshold single-user incident)

**Reviewers:** DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, and the CTO (devex lens). Every finding classified **Mechanical** (engineering correctness or simplification) and was auto-applied. None argued the operator's stated scope should change, so `decision-challenges.md` has no entries.

- **Applied:**
  - first-`^name:` rule and the dedicated self-name message (Kieran P1-1, spec-flow P0/P1-2, CTO DX-1);
  - harness fixes to the H5 loader and the no-orphan check (Kieran P1-2);
  - Phase 3 split into 3a/3b, with RED expectations per test (Kieran P1-3, spec-flow P1-3);
  - inline template rewording and a content-level AC4 (Kieran P1-4, spec-flow P1-4);
  - the missing count sites (Kieran P2-5, arch P2-4);
  - runnable AC6, AC8 and AC11 plus the vitest runner (Kieran P2-6..9);
  - the full battery in 6.1, including agent-originality (spec-flow P1-6, arch P2-2);
  - adapter-rendered Grok stub descriptions (arch P1; narrows D7);
  - dated ADR amendment blockquotes covering the index sentence and the fixture count (arch P2-3);
  - the docs-site blockquote exception recorded (arch P2-5);
  - CTO DX-2 and DX-3.
- **Cut (simplification):**
  - fixtures down from 11 to 6, plus an inline table;
  - the registry-purity set-identity test, the policy-resolution test and the manifest-agreement test, all folded into the per-doc self-name test and the admission count;
  - the c4 row-id assertion;
  - the cross-file sentinel;
  - the `agentLeaves.has` redundancy;
  - the AGENTS.md "Adding a New Domain Leader" step-4 edit;
  - the #8622 disposition from the ADR.
- **Declined:**
  - DHH's "drop the SELF-NAME verdict". Simplicity, the CTO, architecture and the advisor keep it; the per-doc anchor needs a counted verdict.
  - Simplicity's "delete the `discoverAgentPaths` filter". It widens registry semantics for every consumer and buys nothing the per-doc test does not already catch.
  - Simplicity's "drop the closed-frontmatter rule". It is what keeps the carve-out out of the body (Guard 2 row 4).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. That section is filled above.
- **Run `--fix` only on a clean tree.** The CLI refuses a dirty one. Read the whole diff before committing. In #8570, `--fix` rewrote its own evidence. The measured count of evidentiary quotations here is 0, but only a read-through confirms that at work time.
- **Do not trust the census hint blindly for bare leaves.** A leaf that is prose (`copywriter` is also an English word), a filename or an output literal gets reworded instead. The message tail sanctions this with "brace/rename". List every such site in the PR body.
- **Descriptions are double-quoted YAML.** Keep them quoted. An unquoted `:` silently drops a Grok stub (learning 2026-07-11).
- **One count, 67, everywhere live:** registry, manifest, stubs, README ×2, `plugins/soleur/README.md`, `nfr-register.md`, `grok-onboarding.md`, the docs site and `model.c4`. If any disagrees after Phase 5, a derivation is reading a different set. Find which one; do not edit the number.
- **The live-tree mutation rows in AC2 are run by hand and reverted.** A row nobody executed is a paper row.
- **The Grok stub mapping (D7) must touch registry agent ids only.** Mapping `soleur:<skill>` would render a skill as a nonexistent agent stem. Build the id set from `discoverAgentEntries()`, never from a regex over the text.
