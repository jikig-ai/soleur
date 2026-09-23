---
title: "feat(plugin): regenerate-on-conflict works in a self-hosted repo"
date: 2026-09-23
slug: feat-regenerable-conflict-resolution-for-self-hosted-repos
branch: feat-regenerable-manifest
issue: 8542
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

`plugins/soleur/scripts/resolve-regenerable-conflicts.sh` finishes a merge whose only conflicts are
on generated artifacts, by re-deriving each artifact from the merged sources. It is dead in a
self-hosted repo for two independent reasons, and the second is the one that matters more:

1. **The command it would run does not exist there.** Its one hardcoded pair regenerates the C4
   model with `bash scripts/regenerate-c4-model.sh`, a script only this repository has.
2. **Two of its call sites cannot even find the resolver.** Both copies of `pre-merge-rebase.sh`
   load it from `$WORK_DIR/plugins/soleur/scripts/…` — a path inside the *user's* repo — so the
   `[[ -f ]]` test fails and the hook denies `gh pr merge`. Four documented manual invocations,
   including the recovery snippet in `merge-pr/SKILL.md`, are repo-relative in the same way.
   `soleur:ship` and `merge-pr`'s poll loop are the exceptions: they already resolve the resolver
   from `${CLAUDE_PLUGIN_ROOT}` with a `plugin.json` identity check.

So the honest scope is *make the feature reachable and correct for a self-hosted user*, not *teach
the resolver a second command*.

**Coverage bound, stated once so it is not re-litigated:** like the merge driver ADR-210 retired,
this only helps merges driven locally through a Soleur skill. GitHub's Update-branch button and
server-side auto-merge still resolve nothing. #8542's format fix is the part that travels — 107 of
152 replayed pairs merge cleanly for everyone; this change is about the remaining 45 on a local merge.

## Research Reconciliation — Ask vs. Codebase

| Ask claim | Reality | Plan response |
|---|---|---|
| Add a `.soleur/regenerable.tsv` manifest | ADR-235 rejects `A regenerable-artifacts.tsv manifest` by name: "One member; adds a parse surface and invites re-tracking regenerable files." | Cut. The property is delivered by moving the renderer into the plugin. |
| Read the manifest from BASE so a PR cannot inject a command | Moot once no command comes from the repo. | Cut. |
| `soleur:sync` writes the manifest row | Moot. | Cut. |
| "~60 lines / 3 files" | Understated: the reachability fixes alone touch five call sites. | Re-scoped below. |

## Research Insights

### Premise Validation

`#8542` is CLOSED by merged PR #8538. Every cited path exists on `origin/main`. The mechanism the ask
proposed sits in ADR-235's rejected-alternatives table — the stale-mechanism case, recorded above.

### Property List

- **P1.** In a repo with the plugin installed and no repo-local regeneration script, a merge whose
  only conflict is the committed `model.likec4.json` completes and is committed.
- **P2.** The resolver is reachable from every call site that claims to use it, self-hosted included.
- **P3.** A regeneration run writes exactly the conflicted path and no other file.
- **P4.** A failure leaves the tree byte-identical to entry, as today.
- **P5.** A successful exit never commits an artifact derived from sources the merge did not see.

### Cut List

| Mechanism | Property it bought | Why cut |
|---|---|---|
| `.soleur/regenerable.tsv` manifest | P1 for arbitrary artifacts | ADR-235 rejects it; the plugin's own renderer covers the only artifact Soleur writes into customer repos. |
| Reading the manifest from `$BASE` | trust | No repo-supplied command survives. |
| Extracting `renderModelJson()` from the TS producer, plus a `--render-model-json` CLI arm | P1, P3 | The repo already has a self-contained 129-line renderer that writes only the artifact. Moving it is smaller than extracting a second one, keeps `bun` off the merge path, and makes byte-identity between two renderers a non-question. |
| A byte-identity criterion between two renderers | anti-drift | One renderer. |
| Refusing the local arm when it differs from `$BASE` (the former D3) | trust | Unsound as specified: argv resolves before `git merge --no-ff --no-commit` runs, so the check reads HEAD and the execution reads the merged tree. Its predicate was also inverted (`$BASE` is the trusted upstream; HEAD is the PR branch), and the arm's execution closure is larger than the one file it guarded. |
| Two arms with precedence | continuity | One plugin-owned arm; this repo keeps a thin wrapper at the old path for its own callers. |

### Findings that shape the design (each verified against the tree)

1. **`runProducer` writes up to five files** (`guardedWrite` of `generated-components.c4`, three
   `writeIfAbsent` seeds, then the artifact), and the resolver stages only the conflicted path while
   its residual check reads only unmerged paths. Using it would put unrelated writes in the merge
   commit and leave the tree dirty for the next run's clean-tree precondition.
2. **A render-only extraction is not a clean cut.** The render block reads `docs`, `edges`,
   `skipped` and `seeded`; `assessRender`'s gate is `generatedRelationships: edges.length`. A
   standalone renderer either recomputes the component corpus — which does not exist in a customer
   repo — or silently drops that gate.
3. **The repo-local shell renderer is already nearly plugin-resident.** It takes `--out`, gates on
   the likec4 diagnostic text *and* a non-empty element count, publishes atomically, and already
   shells out to the plugin's `lib/c4-canonical-cli.mjs` for canonicalization. Its only repo
   couplings are `REPO_ROOT` derived from its own location and a `spec.c4`/`model.c4`/`views.c4`
   presence guard.
4. **That guard is wrong for customer repos.** `soleur:sync` writes `generated-components.c4`,
   `spec.c4`, `views.c4` and `c4-model.md` — never `model.c4`, which belongs to `soleur:architecture`.
   A plain synced repo fails the all-three check.
5. **`generated-components.c4` is neither tracked nor ignored** (`git ls-files` does not list it;
   `git check-ignore` exits 1). `likec4 export json .` compiles every `.c4` in the directory, so in a
   customer repo the dominant source of the rendered model can be an untracked, machine-local file
   that no merge ever touched. That is P5's whole reason for existing.
6. **ADR-179 sanctions `BASH_SOURCE` for payload scripts** — "Payload scripts use `${CLAUDE_PROJECT_DIR}`
   first and then their own `BASH_SOURCE` location (layout-invariant per ADR-178, and not CWD-derived)".
   The earlier draft of this plan cited the CTO ruling's code-root row as a ban and was wrong.
   `sync-pr-behind.sh` resolving this resolver as a `BASH_SOURCE` sibling is the documented shape.
7. **ADR-179 A11 is a REJECTED item**, and it records that a manifest-plus-name check "is a shape
   check and a `gh pr checkout` tree satisfies it byte-for-byte". The earlier draft cited it as a
   control. It is a cheap sanity check, not a boundary, and the plan says so where it is used.
8. **`${CLAUDE_PLUGIN_ROOT}` is an inherited environment variable**, the same class this script's
   header spends fifteen lines rejecting for `RESOLVABLE_OVERRIDE`. A sibling resolved from the
   running script's own location carries the resolver's own provenance and adds no new trust edge.
9. **The resolver discards its child's output** (`>/dev/null 2>&1`), so the renderer's diagnostic —
   its only observability surface — never reaches the operator; `bail` reports the argv, not the cause.
10. **`likec4` exits 0 on a syntax error**, which is why the renderer's diagnostic-text gate is
    load-bearing and must travel with it.
11. **`manualLayouts` in the committed artifact is an empty object**, and the web editor recomputes
    layout rather than storing hand-positioned geometry, so regeneration does not destroy operator
    layout today. Recorded in Risks because the schema slot exists.

## Decisions

- **D1 — One renderer, moved into the plugin.** `git mv scripts/regenerate-c4-model.sh
  plugins/soleur/scripts/render-c4-model.sh`, add `--root <dir>` (default: `git rev-parse --show-toplevel`),
  resolve `c4-canonical-cli.mjs` as a plugin sibling rather than through the repo, and relax the
  source guard to "at least one `.c4` present" (finding 4). A thin wrapper stays at
  `scripts/regenerate-c4-model.sh` so this repo's freshness test and CI are unchanged.
- **D2 — One arm, anchored on the resolver's own location.** The resolvable set stays one path; its
  argv becomes `bash <PLUGIN_DIR>/render-c4-model.sh --root <REPO_ROOT>`, where `PLUGIN_DIR` is
  `$(dirname "${BASH_SOURCE[0]}")` made absolute **before** the script `cd`s to the repo root.
  `${CLAUDE_PLUGIN_ROOT}` is consulted only if that sibling is absent. Whichever root is used gets the
  `plugin.json` name check — described as a sanity check, not a boundary (finding 7).
- **D3 — Refuse when any `.c4` source is untracked.** Before running the arm, require every `.c4` in
  the diagrams directory to be tracked; otherwise `na`, naming the file. This closes P5 (finding 5).
- **D4 — Enforce P3 in the resolver, not in the renderer.** After the regeneration loop, require
  `git diff --name-only` to be empty or `bail`. Two lines, arm-agnostic, and it holds for any future
  member of the resolvable set.
- **D5 — Make the failure legible.** Capture the arm's combined output, put its last line in the
  `bail` message, wrap the arm in `timeout`, and print one line to stderr before a run that can take
  minutes.
- **D6 — Fix the call sites.** Both `pre-merge-rebase.sh` copies resolve the resolver from
  `${CLAUDE_PLUGIN_ROOT}` with the identity check and fall back to the repo copy; the four documented
  invocations and the `merge-pr` recovery snippet become plugin-anchored.

## Implementation Phases

### Phase 1 — Move the renderer

1. `git mv scripts/regenerate-c4-model.sh plugins/soleur/scripts/render-c4-model.sh`.
2. Add `--root`; derive `DIAGRAMS_DIR` from it; resolve `c4-canonical-cli.mjs` from the script's own
   directory; relax the source guard to "at least one `.c4`".
3. Leave a wrapper at the old path that forwards to the new one with `--root "$(git rev-parse --show-toplevel)"`.
4. Keep the diagnostic-text and element-count gates intact.

### Phase 2 — Resolver

1. Absolutize `PLUGIN_DIR` above the `cd`, and amend the header comment that currently forbids
   `BASH_SOURCE` (it is about the *repo* root; this is the *plugin* root — say so).
2. Replace the hardcoded argv with the single plugin-anchored argv (D2).
3. Add the untracked-source refusal (D3), the post-loop P3 assertion (D4), and the output capture,
   timeout and progress line (D5).

### Phase 3 — Call sites

Both `pre-merge-rebase.sh` copies; `merge-pr/SKILL.md` (recovery snippet + poll loop),
`drain-prs/SKILL.md`, `ship/SKILL.md`, `ship/references/settle-then-admin-merge.md`.

### Phase 4 — Tests and ADRs

Fixtures below; ratchet re-anchored on a marker comment; floor raised to the new case count; ADR-235
amendment (the command moved into the plugin, the set is still one member, the manifest stays
rejected) and an ADR-179 amendment item recording the in-payload sibling carve-out and naming
`sync-pr-behind.sh` as the existing instance.

## Files to Create

- `plugins/soleur/scripts/render-c4-model.sh` (moved, with history).

## Files to Edit

`scripts/regenerate-c4-model.sh` (becomes a wrapper) · `plugins/soleur/scripts/resolve-regenerable-conflicts.sh` ·
`plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh` · `.claude/hooks/pre-merge-rebase.sh` ·
`.openhands/hooks/pre-merge-rebase.sh` · `plugins/soleur/skills/merge-pr/SKILL.md` ·
`plugins/soleur/skills/drain-prs/SKILL.md` · `plugins/soleur/skills/ship/SKILL.md` ·
`plugins/soleur/skills/ship/references/settle-then-admin-merge.md` ·
`plugins/soleur/test/c4-model-freshness.test.sh` (path) · ADR-235 · ADR-179

## Open Code-Review Overlap

None — no open `code-review`-labelled issue names any file above.

## User-Brand Impact

**If this lands broken, the user experiences:** a merge that commits a C4 diagram which does not match
the merged sources — a wrong diagram in the KB viewer — or, in the refusal direction, a merge that
stalls exactly as it does today.

**If this leaks, the user's workflow is exposed via:** no data exposure. The risk is execution: this
code decides what runs on the merging operator's machine during a merge. The design removes the
repo-supplied command rather than validating it, and refuses rather than guessing.

- **Brand-survival threshold:** single-user incident.

## Domain Review

**Domains relevant:** none — plugin tooling with no user-facing surface, pricing, or legal artifact.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-235** (command moved into the plugin; set still one member; manifest still rejected) and
add an **ADR-179** amendment item (in-payload sibling resolved from an absolutized `BASH_SOURCE`,
naming `sync-pr-behind.sh` as the existing instance, and recording that the `plugin.json` check is a
sanity check per A11, not a boundary).

### C4 views

No C4 impact. Checked all three of `model.c4`, `views.c4`, `spec.c4` for external human actors (none
added — the merging operator is modelled), external systems (none — likec4 runs locally and is not a
modelled vendor edge), containers/data stores (none — the artifact is modelled), and access
relationships (unchanged). `plugins/soleur/test/c4-count-parity.test.sh` must be green.

## Observability

```yaml
liveness_signal:
  what: "the resolver's [regen-on-conflict] verdict on stderr, plus SOLEUR_REGEN_ON_CONFLICT with arm= and root= on stdout at rc=0"
  cadence: "per merge that hits a regenerable conflict"
  alert_target: "the invoking skill, which branches on the exit code"
  configured_in: "plugins/soleur/scripts/resolve-regenerable-conflicts.sh"
error_reporting:
  destination: "stderr, plus the arm's captured output tail in the bail message; no off-box sink — this runs on the operator's machine"
  fail_loud: "yes — non-zero exit, tree byte-identical to entry"
failure_modes:
  - mode: "no plugin root resolvable"
    detection: "na naming the missing root and the manual command to run"
    alert_route: "caller falls back; the merge stays conflicted"
  - mode: "an untracked .c4 source in the diagrams directory"
    detection: "na naming the file"
    alert_route: "caller falls back; prevents committing a model the merge never saw"
  - mode: "render exceeds the timeout, or npx is offline"
    detection: "non-zero from timeout; the captured tail names it"
    alert_route: "bail, tree unwound"
  - mode: "likec4 exits 0 with a degenerate model"
    detection: "the renderer's diagnostic-text and element-count gates"
    alert_route: "non-zero, so the resolver bails"
logs:
  where: "stderr of the invoking session; the merge commit is the durable record of success"
  retention: "session-scoped"
discoverability_test:
  command: bash plugins/soleur/scripts/render-c4-model.sh --help
  expected_output: "--root"
```

The probe prints the moved renderer's usage on stdout, which proves the plugin-owned entry point
exists and accepts the flag the resolver passes it. It needs no credentials, touches no git state and
returns immediately. (The previous draft's probe invoked the resolver with no base ref; that writes
its refusal to **stderr**, which preflight Check 10 never matches, so it could not have passed.)

## Guard Contract

### Guard 1 — the resolver only ever executes the plugin-owned renderer

**Property.** Every command the resolver executes resolves from the plugin root that the resolver
itself was loaded from (or `${CLAUDE_PLUGIN_ROOT}` when the sibling is absent), never from a path
supplied by the repository being merged.

**Assembly.** One chokepoint: the function returning the argv for the single resolvable path. Its
only inputs are `PLUGIN_DIR` (absolutized before the `cd`), `${CLAUDE_PLUGIN_ROOT}`, and the identity
check. Execution stays `"${_argv[@]}"` — an array, never a shell. A marker comment
(`# ARGV-SOURCE: plugin`) marks the one site; the suite ratchets on the marker's count and name.

**Mutation matrix.**

| # | Mutation | Must |
|---|---|---|
| m1 | Resolve `PLUGIN_DIR` after the `cd`, or relative to cwd | RED on a fixture whose merged repo ships a decoy `plugins/soleur/scripts/render-c4-model.sh` |
| m2 | Drop the untracked-source refusal | RED on a fixture with an untracked `generated-components.c4` whose content would change the render |
| m3 | Drop the post-loop `git diff --name-only` assertion | RED on a fixture whose renderer stub writes a second file |
| m4 | Point the argv at a repo-relative path | RED on the self-hosted fixture (no repo copy present) |
| m5 | Delete the arm entirely | RED on the self-hosted fixture |
| m6 | Add a second `# ARGV-SOURCE:` site | RED on the ratchet |

**Harness rows.** (a) Delete one new case → the raised floor fires. (b) Must-PASS, non-canonical: a
repo where `scripts/regenerate-c4-model.sh` exists as a wrapper → the plugin renderer still runs and
the merge commits, proving the wrapper is not a second arm.

**Anchor.** The existing ratchet greps the SUT for its `RESOLVABLE_PATHS=(` default and pins the one
member. Re-anchor it on a named marker comment rather than a `tail -1` of every matching assignment,
and extend it to the `# ARGV-SOURCE:` marker so a second argv source is a deliberate edit to a test
that names ADR-235.

## Acceptance Criteria

- **AC1** In a fixture repo with no repo-local renderer, a merge whose only conflict is
  `model.likec4.json` exits 0 and commits; the committed artifact is what the plugin renderer produced.
- **AC2** After that exit 0, `git status --porcelain` is empty — nothing unstaged, nothing left dirty.
- **AC3** With an untracked `.c4` in the diagrams directory, the resolver refuses, names the file, and
  leaves the tree byte-identical (P5).
- **AC4** With a decoy `plugins/soleur/scripts/render-c4-model.sh` in the merged repo, the executed
  renderer is the one beside the running resolver, not the decoy. **This is achievable only for call
  sites that load the resolver from the plugin root** — which is what Phase 3 makes true of the hooks.
  Where the resolver is itself loaded out of the merged tree, its sibling *is* the decoy and no check
  inside the script can change that, so the fixture asserts AC4 against a plugin-root-loaded resolver
  and a separate case documents the other direction as refused-by-Phase-3, not defended-by-the-script.
- **AC5** `plugins/soleur/scripts/render-c4-model.sh --root <fixture>` renders from a directory that
  has `spec.c4` and `views.c4` but no `model.c4` (the shape `soleur:sync` produces).
- **AC6** A `.c4` syntax error makes the renderer exit non-zero and the resolver bail; the bail message
  contains the renderer's diagnostic text, not only the argv.
- **AC7** Every failure path leaves `tree_fp` byte-identical to entry, including a failure occurring
  after the `rm -f` of the conflicted path.
- **AC8** `bash .claude/hooks/pre-merge-rebase.sh`'s resolver lookup finds the plugin copy when the
  repo has none; the `.openhands` copy matches byte-for-byte on that block.
- **AC9** No documented invocation of the resolver or the renderer remains repo-relative:
  `git grep -n 'plugins/soleur/scripts/resolve-regenerable-conflicts.sh'` shows only plugin-anchored
  or `${CLAUDE_PLUGIN_ROOT}`-anchored forms outside tests and ADRs.
- **AC10** `_min_cases` is raised to the new count in the same edit; the suite's verdict and ledger
  reconciliations hold.
- **AC11** ADR-235 and ADR-179 amendments land in this PR; the ratchet's comment still describes what
  it asserts.
- **AC12** `c4-model-freshness.test.sh`, `c4-count-parity.test.sh` and `c4-likec4-version-pin.test.ts`
  are green (the version pin now has one fewer site, not one more).

## Risks / Sharp Edges

- **The `plugin.json` name check is a shape check, not authentication, and the decoy here is not
  hypothetical.** This repository's own `plugins/soleur/.claude-plugin/plugin.json` is tracked and its
  first field is `"name": "soleur"`, so a shadowing copy inside a merged tree carries a *genuine*
  manifest and passes the check. ADR-179 records the same limitation (A11; decision 11 pins it with a
  MUST-PASS row asserting a decoy manifest is accepted). What actually excludes a shadowing copy is
  resolving the root outside the working tree — which is why the ordering in D2 is
  resolver's-own-location first, and why the check is described in the code as defence-in-depth rather
  than as the control.
- **Two of the resolver's own call sites load it from the merged tree.** Phase 3 fixes both. Where an
  attacker controls the whole script, nothing inside it helps; that is a property of the call site, and
  the plan says so rather than implying the script defends itself.
- **Use the bare `${CLAUDE_PLUGIN_ROOT}` form, per ADR-179 A12** — `:-` defaults are recorded there as
  unmigrated and not endorsed, so a new site must not add one.
- **`npx -y likec4@1.50.0` fetches from the registry at merge time** on the operator's machine — a
  third-party execution surface that exists today and is unchanged. The moved renderer should carry
  `--ignore-scripts`, which the TS producer already passes and the shell one does not.
- **`manualLayouts` is empty today** and layout is recomputed, so regeneration destroys no operator
  geometry. If likec4 ever persists hand positions into the artifact, this changes and the refusal
  set needs revisiting.
- **`sync-pr-behind.sh` loses its sibling lookup when ship runs it from a mktemp snapshot**, so the
  DIRTY arm reports "manual resolution required" on a regenerable conflict. Pre-existing, out of scope
  here, and worth its own fix.
