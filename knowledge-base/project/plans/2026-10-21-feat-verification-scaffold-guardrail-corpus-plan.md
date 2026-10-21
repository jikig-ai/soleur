---
title: "feat: verification-scaffold — ship generic guardrail corpus to user repos"
type: feat
date: 2026-10-21
slug: feat-verification-scaffold-guardrail-corpus
branch: feat-one-shot-10404-verification-scaffold
issue: 10404
closes: 10404
priority: p3-low
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

Epic #10397 child 7. Soleur plugin users receive the pipeline (review/qa/ship) but not the
guardrail depth Soleur runs on itself: the `.claude/hooks/` corpus and `scripts/lint-*`
checks are repo-internal, and `constraint-scaffold` already proves the
generate-a-gate-into-user-CI pattern for a single gate. This change audits the hook/lint
corpus for repo-generic entries (no Soleur-domain coupling) and ships a
`verification-scaffold` skill that installs the chosen generic set — at minimum a
secret-scan, an orphan-test registration check, and a commit-on-main guard — into a user
repo's hooks and CI, advisory-first where a gate can block.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10404` is **OPEN** (`gh issue view 10404`), title `feat: verification-scaffold — ship
  generic guardrail corpus to user repos (Epic #10397 child 7)`; no closing PRs. Epic `#10397` OPEN.
- Sibling children: `#10398`, `#10399`, `#10401`, `#10402`, `#10403` CLOSED; child 3 `#10400`
  (property-based-testing guidance) still OPEN — orthogonal, not a dependency.
- `constraint-scaffold` exists at `plugins/soleur/skills/constraint-scaffold/` (SKILL.md +
  `scripts/constraint-scaffold.sh` + 6 `references/*.template` + 5 `test/*.test.sh`) — the
  generate-a-gate-into-user-CI pattern is proven and this plan mirrors its shape.
- `.claude/hooks/` holds **112 entries** (issue says ~121 — drifted; 57 `*.test.sh` siblings).
  `scripts/lint-*` holds **88 files**. Audit population is 200 entries minus fixtures/TSVs.
- `wg-dark-launch-deploy-gates` exists at `AGENTS.rules.md:80` — gating checks ship
  non-blocking first and are observed before they gate. The issue's "advisory-first" is the
  same posture applied to emitted user-repo gates.
- Plugin ships hooks via `plugins/soleur/hooks/hooks.json` (fixed set); repo hooks register
  via `.claude/settings.json` on `$CLAUDE_PROJECT_DIR` paths. The scaffold's delivery target
  is the **user repo's own** `.claude/hooks/` + `.claude/settings.json` + `.github/workflows/`
  — not `hooks.json` (that surface applies unconditionally to every install and is curated
  separately).
- No prior generic-vs-coupled audit of the hook/lint corpus exists (searched
  `knowledge-base/` for audit artifacts).

### Property List (Phase 0.6b)

- P1 — a written audit classifying each `.claude/hooks/` entry and `scripts/lint-*` file as
  generic vs Soleur-coupled, with rationale, exists and is committed.
- P2 — a `soleur:verification-scaffold` skill installs at least secret-scan + orphan-test +
  commit-guard into a user repo's hooks/CI, non-destructively and proven to detect.
- P3 — every emitted gate is advisory-first (warn-mode / non-required check) with a named
  promotion path, per `wg-dark-launch-deploy-gates`.

### Mechanism List + Cut List (Phase 0.6b)

- M1 (audit → P1): no existing artifact covers it. KEEP.
- M2 (`verification-scaffold` skill → P2): `constraint-scaffold` covers ONE gate
  (dependency-cruiser boundary, Next.js-only); nothing else installs generic guards.
  Extending `constraint-scaffold` was considered and cut — it is scoped to one engine and one
  boundary; a registry-driven multi-guard installer is a different mechanism, and merging
  them would couple two generators that evolve on different cadences. KEEP as new sibling.
- M3 (advisory-first emission → P3): reuse `constraint-scaffold`'s proven
  informational/non-blocking model + ADR-071's agent-owns-gates recovery posture rather than
  inventing new machinery. KEEP as a reused pattern, not new mechanism.
- CUT: shipping the corpus via `hooks/hooks.json` — that registry applies unconditionally to
  every Soleur install with no opt-in and no per-repo tailoring; the scaffold's value is
  deliberate per-repo installation.
- CUT: a separate standalone audit document outside the skill — folded into the
  machine-readable registry (`references/guardrail-registry.tsv` carries path/verdict/
  rationale/installable per row) + `references/AUDIT.md` summary; one artifact serves the
  acceptance and the installer, so the audit cannot drift from the install set.

### Repo research (local fan-out, executed inline — no Task substrate in this environment)

- **constraint-scaffold anatomy** (the sibling to mirror): one generator script, POSIX-only;
  non-destructive (refuses overwrite, no `--force`; append-once marker-keyed writes);
  `mkdir` lock in git common dir; bite-proof pass→fail→pass on a detached-HEAD `$TMPDIR`
  worktree; self-cleanup armed before the first write and covering exit codes 66–74/130/143;
  stdout-first `FAILED (<code>):` contract; README + pointer line written LAST (after the
  bite). Tests live in `test/*.test.sh` and are auto-registered by the
  `plugins/soleur/skills/*/test/*.test.sh` glob in `scripts/test-all.sh:98` — new suites need
  no runner edit.
- **Candidate coupling levels** (pre-audit sketch; the audit confirms):
  - `.claude/hooks/git-commit-secret-scan.sh` — PreToolUse `git commit` gitleaks scan;
    soft-coupled (`emit_incident` call is guarded with `command -v … || true`), needs
    `.gitleaks.toml` + gitleaks binary; `lefthook.yml:73-75` carries the canonical
    `gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1` invocation with
    the `GIT_CONFIG_*` color-pinning subtlety that MUST travel with any port (measured:
    `color.diff=always` reports zero findings on a staged key).
  - `guardrails.sh` arms `block-commit-on-main` and `block-stash-in-worktrees` — heavy
    coupling (sources `lib/incidents.sh` fail-soft/fail-hard mix, `lib/freeze-lock.sh`,
    `lib/hook-input.sh`); genericization means extracting standalone arms, not copying.
  - `scripts/lint-orphan-test-suites.sh` — the property (every tracked `*.test.sh` runs
    somewhere) is generic; the implementation enumerates SIX repo-specific registration
    surfaces (`test-all.sh`, `infra-validation.yml`, `run-registered-suites.sh`, workflow
    `run:` shapes, tests/commands loop, exclusion table). Ships as a reduced generic form
    parameterized on runner globs.
  - `scripts/lint-trap-tempfile-ownership.py` — mostly generic static lint (4 narrow rules +
    highwater ratchet); needs baseline regeneration per-repo.
  - `scripts/lint-shell-capture-exit.py`, `lint-shell-trace-credential-refusal.py`,
    `lint-workflow-errexit-capture.py`, `lint-window-closure-assertion.py`,
    `lint-gh-argv-arg.py`, `lint-dual-lockfile.sh` — likely generic candidates the audit
    confirms (they encode shell/CI hygiene properties, not Soleur domain).
- **Delivery shape precedent**: `model.c4` `platform.plugin` already documents plugin→
  user-repo write surfaces (ADR-290 lint-ratchet user mode, `emit-decision.sh`,
  `pipeline-tally.sh`); emitted PreToolUse hook code in a customer session is the NEW
  boundary (hooks run on every tool call, vs lint-ratchet's on-demand run) — the ADR task
  records it.
- **Budget/census constraints**:
  - `SKILL_DESCRIPTION_WORD_BUDGET = 2413`, measured **2413/2413 zero headroom**
    (95 model-visible skills; `disable-model-invocation` skills excluded per ADR-236). A new
    ~25-35 word description needs a bump with a `#10404` justification comment — the
    established pattern (15 prior bumps, each "against an N/N zero-headroom baseline").
  - `components.test.ts` requires `description:` to start with `This skill`.
  - `plugins/soleur/README.md` says `Skills | 103`; `plugins/soleur/skills/` has 104 dirs
    (constraint-scaffold is unlisted — a pre-existing gap; verify at work time). New skill
    adds a row + count.
  - `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` map — unmapped skills render
    `Uncategorized`; add `verification-scaffold` under Workflow.
  - `harness-parity-tree.test.ts` uses `MIN_TRACKED_SKILLS` floor (no edit); agent count
    unaffected (no new agents).
  - `lint-skill-body-budget.py` ceilings pin lifecycle skills only (FSM ∪ destinations ∪
    ONE_SHOT_CHILD_SKILLS); a non-lifecycle skill adds no row — confirm at work time.
- **Institutional learnings that bind this plan**:
  - `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing` —
    mutation matrix needs harness rows + must-PASS rows, not only RED rows.
  - `2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms` (#8288) —
    self-cleanup covers every failure in the write window, not just named codes.
  - `2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself` (best-practices) —
    the install manifest and the emitted set must be bound by a same-diff guard.
  - `2026-03-20-bare-repo-plugin-hook-sync-gap` — a guard living only in repo hooks never
    reaches plugin consumers (this issue IS that gap).
  - `2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing` — verify hook JSON
    output behaviorally in CI, not by inspection.
  - `2026-03-21-lefthook-gobwas-glob-double-star` — glob semantics trap for any emitted
    pre-commit config.
  - `2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan` — the ADR
    ordinal is provisional (siblings can claim it); renumber sweeps all artifacts.

### Community discovery / functional overlap

- No new stack signatures (plugin-internal bash/python tooling; the emission targets any git
  repo). Only `soleur` is installed (`installed_plugins.json`) — no community artifact to
  overlap. `constraint-scaffold` is prior art, not overlap: it generates one boundary gate;
  nothing installs a guard set. Check runs clean — proceeding.

### External research decision

- **Skip.** Strong local context: the corpus being audited is this repo's own, the sibling
  generator exists, and the governing ADRs (071, 074, 290) + learnings are in-tree. External
  research adds nothing to a port-and-package task.

### Research Reconciliation — Spec vs. Codebase

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| "~121 .claude/hooks entries" | 112 entries (57 `.test.sh`) | Audit population = live `ls` at work time; ACs phrase as "every non-fixture entry", not a count |
| "constraint-scaffold already proves the ship-a-gate-into-user-CI pattern" | Confirmed — SKILL.md + generator + templates + bite-proof suite | Mirror its file layout and contracts verbatim where the property matches |
| "expected candidates: secret scan, orphan-test, tempfile-ownership, block-stash" | All four exist; coupling varies (secret-scan soft, orphan-test implementation-coupled, stash an arm inside `guardrails.sh`) | Audit produces the verdicts; plan guarantees only the three acceptance-named installables |

## Problem Statement / Motivation

Soleur plugin users get the workflow pipeline (`plan`/`work`/`review`/`qa`/`ship`) but none
of the deterministic Layer-1 guardrail depth Soleur runs on itself. `.claude/hooks/` (112
entries) and `scripts/lint-*` (88 files) are repo-internal: they exist only because they
live in this checkout, and a founder's product repo — the place their agent actually
commits — has no commit-on-main guard, no staged-secret scan, no orphan-test lint. The
agentic-verification epic (#10397) closes child after child of this self/shipped asymmetry;
this is the corpus ship: take the guardrails that are repo-generic (no Soleur-domain
coupling) and make them installable, the same way `constraint-scaffold` already made one
import-boundary gate installable.

The naive alternative — registering more entries in `plugins/soleur/hooks/hooks.json` — was
cut at Phase 0.6b: `hooks.json` applies unconditionally to every install, cannot be tailored
per repo, and conflates "Soleur's session guards" with "the user's repo guards". The corpus
must be *installed deliberately* into a user's repo, where the agent owns it.

## Proposed Solution

Two phases, matching the issue's own split.

### Phase A — The audit (acceptance: written audit list)

Enumerate every non-fixture entry in `.claude/hooks/` (hook scripts, `.test.sh` companions,
libs, TSV/payload docs — each gets a row; companions classify with their parent) and every
`scripts/lint-*` file. Classify each row into one verdict:

- `generic` — the property holds in any git repo AND the implementation is portable as-is.
- `generic-with-extraction` — the property is generic but the implementation is
  Soleur-coupled (sourced libs, hardcoded surfaces); ships only as a reduced/templated
  variant.
- `soleur-coupled` — encodes Soleur domain: `knowledge-base/` paths, the AGENTS rule corpus,
  brand/marketing checks, vendor names (Doppler/Sentry/Better Stack/Supabase/Hetzner),
  plugin-component census, PR/issue workflow conventions, memory-backstop/session-loader
  machinery.

Coupling detectors grepped per row: `.claude/hooks/lib/` source lines, `SOLEUR_*` env vars,
`knowledge-base/`, `apps/web-platform`, `plugins/soleur`, vendor names, `emit_incident`,
rule-id literals. Output is **one machine-readable registry** —
`plugins/soleur/skills/verification-scaffold/references/guardrail-registry.tsv` — columns:
`path | kind | verdict | rationale | installable | emitted_artifact | notes` — plus
`references/AUDIT.md` (method, counts, install-set rationale, deferred candidates). The
registry IS the audit list and IS the install manifest: the installer derives its set from
`installable: yes` rows, so the audit can never drift from what ships (the
registry-anchor learning, 2026-09-14).

### Phase B — `verification-scaffold` skill (constraint-scaffold sibling)

`verification-scaffold.sh` modes: `--list` (print the installable set from the registry),
`--install [guard…]` (default: the full installable set). `--install` emits into the target
repo, mirroring `constraint-scaffold.sh`'s contract — POSIX-only, non-destructive (refuses
to overwrite; append-once marker-keyed writes; no `--force`), `mkdir` lock in the git common
dir, self-cleanup armed before the first write and covering every failure in the write
window (#8288), stdout-first `FAILED (<code>):` lines, README/pointer written LAST after the
bite-proof.

**Delivery shape (hybrid — each guard goes where it bites in this repo):**

| Guard | Emitted artifact(s) | Surface |
|---|---|---|
| secret-scan | `.claude/hooks/soleur-secret-scan.sh` + `.gitleaks.toml` (only if absent) + a gitleaks step in the gates workflow | PreToolUse `Bash` on `git commit` (hook) + full-history scan (CI) |
| commit-guard (block-commit-on-main + block-stash arms, extracted standalone) | `.claude/hooks/soleur-commit-guard.sh` | PreToolUse `Bash` (hook) |
| orphan-test | `scripts/soleur/lint-orphan-tests.sh` + step in the gates workflow | CI (tree scan — too heavy for per-tool-call) |
| tempfile-ownership *(conditional — ships only if the audit clears its baseline mechanism)* | `scripts/soleur/lint-tempfile-ownership.py` + step in the gates workflow | CI |

`settings.json` merge: the hook registrations are merged into the user's
`.claude/settings.json` **via `node`** (guaranteed present for any Claude Code user; `jq`
fallback), idempotent and marker-keyed under a `soleur-verification` comment field the
emitted hooks live beneath — never rewriting the user's existing entries. If neither `node`
nor `jq` resolves, the script refuses before the first write and names the dependency.

**Advisory-first (acceptance: `wg-dark-launch-deploy-gates` posture).** Every emitted gate
ships warn-only by default and names its promotion path:

- Emitted hooks read `SOLEUR_GUARDS_MODE`; unset/`warn` → `permissionDecision: allow` +
  `systemMessage` naming the finding; `enforce` → `deny`. The bite-proof asserts BOTH modes.
- The emitted workflow is `continue-on-error: true` / always-runs-with-real-conclusion
  (constraint-gates.yml's informational shape) until the user marks it required.
- The emitted README names the flip (`SOLEUR_GUARDS_MODE=enforce` in env; mark the check
  required in branch protection) as an agent-owned step — ADR-071's agent-owns-gates model.

**Bite-proof (adapted for advisory gates).** `constraint-scaffold` proves pass→fail→pass;
here the proof runs in a detached-HEAD `$TMPDIR` worktree of the target repo: install → run
each emitted guard on clean input (must pass/emit nothing) → inject each violation (a staged
secret-shaped fixture string, `git commit` on the default branch, `git stash`, an
unregistered `*.test.sh`) → assert each guard's detection line on stdout in warn mode AND
its block in enforce mode → revert → clean again. A gate that cannot detect is not a gate,
advisory or not.

## Technical Considerations

- **Genericization is extraction, not copy.** `guardrails.sh` arms source
  `lib/{incidents,freeze-lock,hook-input}.sh`; the emitted commit-guard is a standalone
  script that parses the PreToolUse stdin JSON itself (the hook-input contract is ~30 lines
  of jq/node-free parsing — verify against `lib/hook-input.sh`'s contract) and carries no
  lib dependency. `emit_incident` calls are dropped (emitted hooks write stdout only —
  no telemetry sink in a user repo).
- **The color-pin travels.** The measured `color.ui=always`/`color.diff=always` zero-finding
  gitleaks trap (`lefthook.yml:55-75`, `git-commit-secret-scan.sh`) is part of the
  secret-scan template — drop it and the emitted scan silently reports zero findings.
- **Orphan-test ships reduced.** The Soleur version enumerates six repo-specific
  registration surfaces; the emitted form ships a declared runner-surface set (a
  `RUNNER_GLOBS` block the installer seeds with the emitted workflow + any detected
  `test-all.sh`/Makefile/lefthook.yml) — the property stays "every `*.test.sh` is run by
  something", the assembly is parameterized at emit time.
- **`.gitleaks.toml` is emit-only-if-absent.** Never merge into a user's existing config —
  print a notice instead; their rules win.
- **New trust boundary.** Emitted hook code runs on every `Bash` tool call in the user's
  session — the first plugin-shipped code that executes *in a customer session* rather than
  on demand (contrast ADR-290 lint-ratchet user mode). Recorded in the ADR.
- **NFR impacts:** none register — no serving surface, no data store, no schema change. The
  corpus is repo tooling; availability/performance NFRs of the platform are untouched.

## User-Brand Impact

- **If this lands broken, the user experiences:** a `verification-scaffold` run that emits
  gates which fail open — a staged key, a commit on main, or an orphan test sails past the
  guard they installed it to catch — or, inverted, warn-mode noise on every `git` call in
  their session until they uninstall.
- **If this leaks, the user's [data / workflow / money] is exposed via:** emitted hook code
  executing on every `Bash` call in their session — the highest-trust surface the plugin
  ships; a defective or vacuous emitted gate is protection they believe they have and do
  not.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** a corpus defect is uniform across every adopter —
  a pattern, not a bespoke single-tenant breach; the emitted artifacts run entirely in the
  user's repo with no egress, no writes outside it, and warn-first semantics, so the worst
  case is absence-of-protection (their CI still scans at push, as ours does) rather than a
  new exposure Soleur introduces. `single-user incident` was considered — it is the honest
  read if one founder's leaked key is ever traced to a vacuous emitted gate — and is
  recorded in `decision-challenges.md` for the review panel.

## Files to Create

- `plugins/soleur/skills/verification-scaffold/SKILL.md` — usage, advisory-first contract,
  agent-owns-gates recovery, install/refresh/uninstall surface.
- `plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh` — the
  generator: `--list` / `--install` / audit-driven emission, lock, self-cleanup, settings
  merge (node/jq), bite-proof.
- `plugins/soleur/skills/verification-scaffold/references/guardrail-registry.tsv` — the
  audit + install manifest (one row per corpus entry).
- `plugins/soleur/skills/verification-scaffold/references/AUDIT.md` — audit method, counts,
  verdict summary, deferred candidates.
- `plugins/soleur/skills/verification-scaffold/references/secret-scan-hook.template`
- `plugins/soleur/skills/verification-scaffold/references/commit-guard-hook.template`
- `plugins/soleur/skills/verification-scaffold/references/lint-orphan-tests.template`
- `plugins/soleur/skills/verification-scaffold/references/verification-gates-workflow.template`
- `plugins/soleur/skills/verification-scaffold/references/gitleaks-config.template`
- `plugins/soleur/skills/verification-scaffold/references/emitted-readme.template` — the
  marker-keyed block appended to the user's hook README / created `SOLEUR-GUARDS.md`.
- `plugins/soleur/skills/verification-scaffold/test/generator.test.sh` — install modes,
  refuse-overwrite, self-cleanup arms, settings-merge idempotence.
- `plugins/soleur/skills/verification-scaffold/test/registry-parity.test.sh` — Guard 1.
- `plugins/soleur/skills/verification-scaffold/test/emitted-guards.test.sh` — fixture-repo
  bite batteries for Guards 2–4.
- `knowledge-base/engineering/architecture/decisions/ADR-295-verification-scaffold-generic-guardrail-corpus.md`
  — provisional ordinal.
- `plugins/soleur/skills/verification-scaffold/references/lint-tempfile-ownership.template`
  — *conditional*: only if the audit clears its per-repo baseline mechanism.

## Files to Edit

- `plugins/soleur/test/components.test.ts` — bump `SKILL_DESCRIPTION_WORD_BUDGET` by the
  measured words of the new `description:` (est. +~28) with a `#10404` justification comment,
  per the 15-bump precedent.
- `plugins/soleur/README.md` — Skills count 103→104 (verify against live
  `ls plugins/soleur/skills | wc -l` = 104 pre-change; constraint-scaffold's absence from the
  tables is a pre-existing gap — confirm whether the count enumerates tables or dirs) + a
  `verification-scaffold` row under Workflow.
- `plugins/soleur/docs/_data/skills.js` — add `verification-scaffold` → `Workflow` in
  `SKILL_CATEGORIES`.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — extend `platform.plugin`'s
  description with the emitted-corpus user-repo surface (no new elements/edges — see
  Architecture Decision).

## Implementation Phases

### Phase 1 — The audit

- Enumerate the corpus (`.claude/hooks/` non-fixture entries + `scripts/lint-*`), run the
  coupling detectors, write `guardrail-registry.tsv` + `AUDIT.md`. Every row gets a verdict
  + one-line rationale. The `installable` set is finalized here — minimum:
  `git-commit-secret-scan.sh`, `guardrails.sh` arms `block-commit-on-main` +
  `block-stash-in-worktrees`, `lint-orphan-test-suites.sh`; candidates `lint-trap-tempfile-ownership.py`,
  `lint-shell-capture-exit.py`, `lint-shell-trace-credential-refusal.py`,
  `lint-workflow-errexit-capture.py`, `lint-window-closure-assertion.py`,
  `lint-gh-argv-arg.py`, `lint-dual-lockfile.sh` per verdict.
- File ONE tracking issue for `installable: deferred` rows (the deferred-corpus backlog).

### Phase 2 — Templates

- Extract/genericize the emitted artifacts listed in Files to Create. Each template carries
  `SOLEUR_GUARDS_MODE` warn/enforce semantics where it can block, the color-pin where it
  scans secrets, and zero lib/vendor coupling. Verify no template references `.claude/hooks/lib/`,
  `knowledge-base/`, `SOLEUR_` outside the documented `SOLEUR_GUARDS_MODE` knob, or
  `plugins/soleur` internals (grep the templates as a shipped-artifact check).

### Phase 3 — Generator

- `verification-scaffold.sh`: argument parse, repo-shape preconditions, `mkdir` lock,
  registry-driven emission (the TSV's `installable: yes` rows → `emitted_artifact` paths),
  `settings.json` merge, bite-proof, README/pointer-last, self-cleanup.

### Phase 4 — Tests

- The three `test/*.test.sh` suites above. Every Guard Contract row gets a battery.

### Phase 5 — Wiring

- `SKILL.md` (description ≤ 30 words, starts `This skill`), README count + row,
  `docs/_data/skills.js` category, `components.test.ts` budget bump, ADR-295, `model.c4`.

### Phase 6 — Verify

- Suite green (`bash scripts/test-all.sh` affected shard), `bun test
  plugins/soleur/test/components.test.ts`, a real dogfood `--install` into a scratch repo
  proving the acceptance set end-to-end, and the deferral issue filed for deferred rows.

## Open Code-Review Overlap

3 open code-review issues touch planned files; all **Acknowledge** (unrelated concerns in
shared files — folding them in would be scope growth, and each has its own re-eval trigger):

- `#8593` — the #6793 probe gate inside `components.test.ts` is narrowed; this plan edits
  only the adjacent `SKILL_DESCRIPTION_WORD_BUDGET` constant. Different concern, own cycle.
- `#9705` — inngest heartbeat review evidence; `model.c4` mention is incidental to that PR's
  diff. This plan's C4 edit is a plugin-description line, unrelated.
- `#8800` — `test-all-affected.test.sh` census-fixture write-through hazard; the
  `lint-orphan-test-suites` mention is incidental. Recorded as audit context, not folded.

## Observability

The deliverable is guardrail machinery; its observability is its own suite — a guard that
silently stops detecting is the failure this repo has paid for repeatedly.

```yaml
liveness_signal:
  what: verification-scaffold suite green — registry-parity, emitted-guard bite batteries,
    self-cleanup arms — plus components.test.ts description budget
  cadence: per-PR affected shard + full suite on merge (auto-registered via
    scripts/test-all.sh:98 glob plugins/soleur/skills/*/test/*.test.sh)
  alert_target: PR CI failure (required shard)
  configured_in: plugins/soleur/skills/verification-scaffold/test/*.test.sh +
    plugins/soleur/test/components.test.ts + scripts/test-all.sh

error_reporting:
  destination: CI stdout — the script prints `verification-scaffold: FAILED (<code>): <msg>`
    mirroring constraint-scaffold's stdout-first contract (no Sentry/telemetry sink ships to
    user repos)
  fail_loud: named exit code per failure arm + last-40-lines log tail on bite failures

failure_modes:
  - mode: registry row declares installable with no emitted template (or reverse)
    detection: registry-parity.test.sh — every installable:yes row ↔ template ↔ --list entry
    alert_route: PR CI failure
  - mode: emitted guard vacuous — fails to detect its own injected violation
    detection: emitted-guards.test.sh fixture-repo battery (warn line AND enforce block)
    alert_route: PR CI failure
  - mode: skill description budget regression on a sibling
    detection: components.test.ts SKILL_DESCRIPTION_WORD_BUDGET assertion
    alert_route: PR CI failure
  - mode: install leaves residue after mid-write failure
    detection: generator.test.sh kill/INT/missing-template arms assert byte-identical tree
    alert_route: PR CI failure

logs:
  where: CI job logs (test-all shard) + script stdout/stderr
  retention: GitHub Actions log retention

discoverability_test:
  command: bash plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh --list
  expected_output: secret-scan
```

## Architecture Decision (ADR/C4)

The plan makes an architectural decision: **emitted PreToolUse hook code is a new
customer-session execution surface.** Prior plugin→user-repo surfaces execute on demand
(`lint-ratchet.py` user mode, ADR-290 Amendment 1) or write only artifacts
(`emit-decision.sh`, `pipeline-tally.sh`, constraint-scaffold's CI files). Emitted hooks run
on every `Bash` tool call in a customer session — first shipped code in the session's tool
loop, not invoked by it.

- `### ADR` — create **ADR-295** (provisional — the ordinal is claimed at ship time against
  `origin/main`; a collision renumbers across plan, tasks, ADR file, and any AC naming it in
  one edit per the 2026-07-05 renumber-sweep learning): *Ship the repo-generic guardrail
  corpus as emitted artifacts into user repos — hooks for command-boundary guards, CI for
  tree-shape lints, warn-first with an agent-owned promotion path.* Alternatives the ADR
  records: (a) extend `hooks/hooks.json` — rejected, unconditional per-install and
  untailorable; (b) widen `constraint-scaffold` — rejected, one engine one boundary; (c)
  docs-only guidance — rejected, the gap is machinery not prose.
- `### C4 views` — update `platform.plugin`'s description in `model.c4` to name the emitted
  corpus surface (it already enumerates prior user-repo surfaces; this is the next one).
  **No new elements/edges** — checked per the completeness mandate: external human actor =
  the installing user (already `founder`); external system = gitleaks binary (a tool like
  dependency-cruiser, deliberately unmodeled as an element); container touched =
  `platform.plugin` only; the plugin→user-repo write relationship is already described in
  the element's prose (ADR-290 Amendment 1 surface); hook execution inside the user's
  session is already the `hooks`/`claude` container's stated behavior. `views.c4` includes
  `platform.plugin` already — no view lines added.
- `### Sequencing` — the ADR is authored in this PR (`status: accepted`), not deferred.

## Guard Contract

### Guard 1 — Registry ↔ emission parity (`test/registry-parity.test.sh`)

**Property.** Every `installable: yes` row in `guardrail-registry.tsv` produces exactly one
emitted artifact path the installer can emit and `--list` prints, and every emitted artifact
traces to exactly one such row — the registry is the single enumeration.

**Assembly.** Three surfaces bound at one chokepoint: the registry's `installable: yes` row
set, the `references/*.template` dir, and the emission table inside
`verification-scaffold.sh`. The registry is the chokepoint — both other surfaces are derived
from it in the same diff; a member added outside it is caught by the test.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add `installable: yes` row naming a nonexistent template | RED |
| 2 | Delete a template an `installable: yes` row names | RED |
| 3 | Remove an installable row from the script's emission table (row + template stay) | RED |
| 4 | Empty the registry's installable set (0 rows parsed, suite exits 0) | RED — vacuous-dispatch row |
| 5 | A second installable row added after a compliant first, template present but not emitted | RED |
| 6 | `installable: no` row with an orphan template present | must-PASS — the suite asserts non-installables are not emitted, never that all templates are installable |

### Guard 2 — Emitted commit-guard (`test/emitted-guards.test.sh`, commit-guard arm)

**Property.** In `enforce` mode no `git commit` on the target repo's default branch and no
`git stash` reaches execution; in `warn` mode the same inputs produce the finding line and
an `allow`.

**Assembly.** Two chokepoints, both asserted: (a) the hook's command scan over the
PreToolUse stdin envelope — every command string reaching `Bash` flows through the JSON
parse + the anchored `git commit`/`git stash` matchers; (b) the `settings.json`
registration merge — an unregistered hook is a guard that checks 0 commands, so the suite
asserts the emitted settings entry exists and points at the emitted path.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Weaken the `git commit` matcher to match only at line-start (chained `x && git commit` sails) | RED |
| 2 | Remove the settings.json registration entry from the emitted merge | RED — guard's own dispatch |
| 3 | Add a second arm (`git stash`) after a compliant `git commit` arm, unregistered in dispatch | RED |
| 4 | Reorder: check branch BEFORE parsing stdin (a non-commit command on main short-circuits) | RED — order/lifetime row |
| 5 | `git commit` on a feature branch | must-PASS — allowed, emits nothing |
| 6 | `git stash` while `SOLEUR_GUARDS_MODE=warn` (unset) | must-PASS — `allow` + finding line, never `deny` |

### Guard 3 — Emitted secret-scan (`test/emitted-guards.test.sh`, secret-scan arm)

**Property.** A staged secret-shaped string never reaches a commit in `enforce` mode, and a
missing gitleaks binary degrades to warn — never to crash and never to silence.

**Assembly.** Three chokepoints: the staged-index scan invocation (the pinned
`gitleaks git --pre-commit --staged` call with the `GIT_CONFIG_*` color pins — the only
place findings are produced), the `.gitleaks.toml` presence check, and the binary-presence
degradation branch. CI's full-history step is the second net, out of scope of the hook's
property.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `GIT_CONFIG_PARAMETERS` color pin | RED — `color.diff=always` run reports 0 findings on a staged key (measured in-repo) |
| 2 | Flip the missing-binary branch from warn to silent allow | RED — degradation arm is the dispatch floor |
| 3 | Scan only the first staged file (second staged file carrying the secret sails) | RED — second-member row |
| 4 | Swap `--staged` for an unstaged diff scan | RED — the property is about the staged index |
| 5 | Clean staged file | must-PASS — `allow`, no finding |
| 6 | User repo already has `.gitleaks.toml` | must-PASS — installer does not overwrite; hook uses their rules |

### Guard 4 — Emitted orphan-test lint (`test/emitted-guards.test.sh`, lint arm)

**Property.** Every tracked `*.test.sh` in the target repo is run by at least one declared
runner surface, or the lint names it.

**Assembly.** The producer (`git ls-files '*.test.sh'`) union the declared `RUNNER_GLOBS`
surface set the emitted lint scans — seeded by the installer from the emitted workflow plus
any detected `test-all.sh`/`Makefile`/`lefthook.yml`. The producer line is the chokepoint:
it is the single place the population is enumerated.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Scope the producer to `scripts/*.test.sh` instead of repo-wide `git ls-files` | RED — plausible-subset row |
| 2 | Empty `RUNNER_GLOBS` (producer enumerates, zero surfaces match) | RED — every suite flagged; the battery asserts the lint reports ≥1, not that it exits 0 |
| 3 | Producer enumerates zero files (glob returns nothing) while a `*.test.sh` exists | RED — vacuous-dispatch row |
| 4 | A second unregistered `*.test.sh` added after a compliant first | RED — second-member row |
| 5 | Registered suite + a path-keyed exclusion row with an issue ref | must-PASS — exclusions are recorded decisions, not failures |

### Guard 5 — Scaffold write-window self-cleanup (`test/generator.test.sh`)

**Property.** A failure anywhere between the first emitted write and the bite-proof's end
leaves the target tree byte-identical to pre-install — cleanup is a property of the window,
not of named failure arms (#8288).

**Assembly.** The ordered emit list inside `verification-scaffold.sh` — every write site
between the armed trap and the disarm point (templates → settings merge → workflow →
README/pointer). Chokepoint: the single `emit()` path every artifact flows through; the
README/pointer writes sit AFTER the disarm point and degrade to warnings.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Send TERM after the third emitted file | RED — all three removed, tree byte-identical |
| 2 | Remove one template mid-suite (failure at its emit site) | RED — prior emissions removed |
| 3 | Move the trap arm to AFTER the first write | RED — exit-site-table row: the first write escapes cleanup |
| 4 | `set -e` abort on a failed `node` merge inside the window | RED — aborts inside the window clean |
| 5 | Second `--install` on an installed repo | must-PASS — refuses overwrite AND deletes nothing from the first run |
| 6 | Emitted settings merge run twice | must-PASS — idempotent: one marker-keyed entry, user's own entries untouched |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "(1) audit the ~121 .claude/hooks/ entries + scripts/lint-* linters for repo-generic candidates (no Soleur-domain coupling) — expected candidates: secret scan, orphan-test registration, tempfile-ownership, block-stash-in-worktrees" | Phase 1 + `guardrail-registry.tsv` + `AUDIT.md` | mapped |
| 2 | "(2) build a `verification-scaffold` skill as a constraint-scaffold sibling that installs the chosen generic set into a user repo's hooks/CI" | Phases 2–5 + SKILL.md + `verification-scaffold.sh` + templates | mapped |
| 3 | "A written audit list: which hooks/lints are generic vs Soleur-coupled, with rationale." | `guardrail-registry.tsv` (verdict + rationale columns) + `AUDIT.md` | mapped |
| 4 | "Users can scaffold at least the secret-scan + orphan-test + commit-guard set into their own repo." | emitted artifacts + `--install` + bite batteries (Guards 2–4) | mapped |
| 5 | "Shipped gates are advisory-first per `wg-dark-launch-deploy-gates` where they can block." | `SOLEUR_GUARDS_MODE` warn-default + continue-on-error workflow + promotion path | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `guardrail-registry.tsv` + `AUDIT.md` | "A written audit list: which hooks/lints are generic vs Soleur-coupled, with rationale." | asked |
| `verification-scaffold` SKILL.md + generator + templates | "build a `verification-scaffold` skill as a constraint-scaffold sibling" | asked |
| Emitted secret-scan / commit-guard / orphan-test | "Users can scaffold at least the secret-scan + orphan-test + commit-guard set" | asked |
| Warn-mode hooks + non-required workflow | "Shipped gates are advisory-first per `wg-dark-launch-deploy-gates`" | asked |
| `test/*.test.sh` suites + mutation batteries | — | inferred — justification: every emitted guard needs a red-able battery per the Guard Contract gate; a shipped guard with no suite is the vacuity class |
| `components.test.ts` budget bump | — | inferred — justification: 2413/2413 measured zero headroom; the new description cannot land without it |
| `README.md` count/row + `skills.js` category | — | inferred — justification: plugin component-count contract (pre-commit checklist) and docs-site categorization |
| ADR-295 + `model.c4` description | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — emitted session-hook code is a new trust boundary that must be recorded in the same diff |
| Deferral tracking issue for `installable: deferred` rows | — | inferred — justification: plan Phase 6 deferral-tracking rule — a deferral without a tracker is invisible |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `knowledge-base`, (plus emitted artifacts *in*
  the user's repo, not this diff)
- Planned files: ~20 (15 create + 5 edit) | Estimated changed lines: ~2,200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — over the estimated-lines threshold; split rejected because
  the audit registry and its installer are bound by Guard 1's same-diff parity (a split
  lands an unverified registry or an unmanifested installer first).

## Acceptance Criteria

- [ ] `guardrail-registry.tsv` + `AUDIT.md` are committed and classify **every**
  non-fixture `.claude/hooks/` entry and every `scripts/lint-*` file with a verdict
  (`generic` / `generic-with-extraction` / `soleur-coupled`) and a one-line rationale.
- [ ] `bash plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh --list`
  prints the installable set derived from the registry (includes `secret-scan`,
  `commit-guard`, `orphan-test`).
- [ ] `--install` into a scratch git repo emits `.claude/hooks/soleur-secret-scan.sh`,
  `.claude/hooks/soleur-commit-guard.sh`, `.github/workflows/soleur-verification-gates.yml`,
  emitted lint script(s), and merges `.claude/settings.json` without rewriting the user's
  existing entries.
- [ ] Advisory-first: emitted hooks default to warn (`allow` + finding line), the emitted
  workflow is `continue-on-error`/non-required, and the emitted README names the promotion
  path (`SOLEUR_GUARDS_MODE=enforce`, mark-check-required).
- [ ] Bite-proof green: in a fixture repo each emitted guard detects its injected violation
  in BOTH warn and enforce modes and stays quiet on clean input.
- [ ] Non-destructive: a second `--install` refuses overwrite without deleting; every
  failure inside the write window leaves the tree byte-identical (kill/TERM/missing-template/
  node-failure arms).
- [ ] `test/generator.test.sh`, `test/registry-parity.test.sh`, `test/emitted-guards.test.sh`
  exist under `plugins/soleur/skills/verification-scaffold/test/` and are green — every
  Guard Contract matrix row has a battery.
- [ ] `bun test plugins/soleur/test/components.test.ts` is green with the bumped
  `SKILL_DESCRIPTION_WORD_BUDGET` and its `#10404` justification comment.
- [ ] `plugins/soleur/README.md` skills count/row updated; `docs/_data/skills.js` categorizes
  `verification-scaffold`.
- [ ] `ADR-295` (or the renumbered ordinal) is committed in the same PR; `model.c4`'s
  `platform.plugin` description names the emitted-corpus surface.
- [ ] One tracking issue filed for `installable: deferred` registry rows.
- [ ] No emitted template references `.claude/hooks/lib/`, `knowledge-base/`,
  `apps/web-platform`, or `SOLEUR_` outside the documented `SOLEUR_GUARDS_MODE` knob
  (shipped-artifact grep in the suite).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — plugin tooling / CI scaffold. The mechanical
UI-surface override was checked: every file in Files to Create/Edit is `.md`/`.sh`/`.tsv`/
`.template`/`.ts`/`.js`/`.c4` — no UI-surface term or glob match, so Product/UX tier is NONE
and no `.pen` is required. GDPR gate checked and skipped: no regulated-data surface
(schemas/migrations/auth/API/SQL); the (a)–(d) expansion triggers were evaluated — the
emitted corpus is generic guard code that scans the user's own staged index locally with
zero egress, not an operator-data movement surface.

## Test Scenarios

- **unit:** Given a registry with an `installable: yes` row and no template, when
  `registry-parity.test.sh` runs, then it reports the row and exits non-zero (Guard 1 row 1).
- **unit:** Given `SOLEUR_GUARDS_MODE` unset and a staged fake key, when the emitted
  secret-scan hook runs on `git commit`, then stdout carries `allow` + the finding line; the
  same input under `enforce` produces `deny` (Guard 3 + advisory-first).
- **integration:** Given a scratch repo on `main` with the commit-guard installed, when
  `git commit` is invoked on `main`, then the emitted hook denies (enforce) / warns (warn);
  on a feature branch it allows and emits nothing (Guard 2 rows 5–6).
- **integration:** Given a fixture repo where the installer is SIGTERMed after the third
  emitted file, when the suite diffs the tree, then it is byte-identical to pre-install
  (Guard 5 row 1).
- **integration:** Given `color.diff=always` in the environment, when the emitted
  secret-scan runs against a staged key, then it still reports the finding (Guard 3 row 1).
- **e2e (pyramid-justified: the deliverable is a repo-level installer; only a real
  install+commit cycle exercises settings merge, hook registration and the violation path
  end-to-end):** `verification-scaffold.sh --install` into a scratch repo → all four
  violation classes injected → each emitted gate detects in warn mode → flip to enforce →
  each blocks → uninstall/revert → tree clean.

## Success Metrics

- `--install` completes the acceptance set in a scratch repo with zero manual steps.
- Every Guard Contract matrix row has a failing-then-passing battery (red-able, never
  satisfied by a no-op).
- Audit covers 100% of the non-fixture corpus; zero `installable` rows ship without an
  emitted artifact (parity guard green).

## Dependencies & Risks

- **Orphan-test reduction may under-detect** in user repos whose runner surfaces the seeded
  `RUNNER_GLOBS` misses — mitigated by the installer seeding from detected
  `test-all.sh`/`Makefile`/`lefthook.yml`/workflow files and the lint printing its surface
  set on every run.
- **Emitted hook JSON parsing must match the PreToolUse envelope** — the contract is pinned
  by `.claude/hooks/lib/hook-input.sh` + the payload-shape docs; the emitted parser is
  tested against fixture envelopes, not just happy-path input.
- **`settings.json` merge on malformed user JSON** — the merge fails closed (parse error →
  refuse before first write, name the file), never rewrites blindly.
- **ADR-295 ordinal collision** — re-verified against `origin/main` at ship time; a renumber
  sweeps plan/tasks/ADR/ACs in one edit.
- **gitleaks absent on user machines** — emitted hook warns (advisory-first) and the CI step
  installs the pinned binary; the load-bearing scan is never the local-only one.

## Non-Goals

- Shipping Soleur-coupled guards (ship-* gates, brand checks, KB guards, filing gates,
  memory-backstop) — the audit's `soleur-coupled` verdicts stay repo-internal by design.
- `hooks/hooks.json` registration (cut at Phase 0.6b).
- Enforce-mode defaults — promotion is a separate deliberate step per
  `wg-dark-launch-deploy-gates`.
- Porting the corpus to non-Claude harnesses' hook registries — the emitted surface is the
  Claude `.claude/` convention + generic CI; harness ports are deferred scope.
- Auto-recovery dispatchers for emitted gates (constraint-scaffold's ADR-074 two-stage
  machinery) — the founder's own agent owns gate maintenance; no privileged workflow ships.

## References & Research

- `plugins/soleur/skills/constraint-scaffold/` — the sibling: generator, templates,
  bite-proof, self-cleanup, exit-code contract.
- `.claude/hooks/guardrails.sh` — the arm source for commit-guard (`block-commit-on-main`,
  `block-stash-in-worktrees`).
- `.claude/hooks/git-commit-secret-scan.sh` + `lefthook.yml:55-110` — the secret-scan source
  + the color-pin subtlety.
- `scripts/lint-orphan-test-suites.sh` — the six-surface registration model being reduced.
- `AGENTS.rules.md:80` — `wg-dark-launch-deploy-gates` (advisory-first posture).
- `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md` —
  agent-owns-gates recovery model.
- `knowledge-base/engineering/architecture/decisions/ADR-290-shrink-only-lint-ratchet-keyed-on-file-rule-anchor.md`
  — plugin→user-repo on-demand surface precedent.
- `knowledge-base/project/learnings/2026-09-19-cleanup-on-failure-is-a-property-of-the-window-not-the-arms.md`
  — the self-cleanup window property.
- `knowledge-base/project/learnings/best-practices/2026-09-14-a-registry-that-carries-its-own-hash-certifies-itself.md`
  — registry↔emission same-diff anchoring.
- Issue: #10404 · Epic: #10397 · Sibling specs:
  `knowledge-base/project/specs/archive/20261020-171633-feat-one-shot-10399-webplat-feature-map/`,
  `…/20261021-074512-feat-one-shot-10403-flake-quarantine-guidance/`

## Research Insights

### Premise Validation (Phase 0.6)

- `#10404` OPEN; epic `#10397` OPEN. Sibling children shipped one PR each:
  `#10401`→PR #10727, `#10402`→PR #10735, `#10403`→PR #10738 (all COMPLETED); `#10400` open.
- `.claude/hooks/` = **112 files, 55 non-test `.sh`** (issue says "~121 hooks" — stale
  count; directionally right, the corpus is large).
- All four expected candidates exist but with different shapes:
  `git-commit-secret-scan.sh` (standalone hook, 315 lines, depends on
  `.claude/hooks/lib/hook-input.sh` + gitleaks + repo-root `.gitleaks.toml`),
  `scripts/lint-orphan-test-suites.sh` (1276 lines, hardcodes `scripts/test-all.sh`,
  `TEST_GROUP`/`SCRIPTS_SHARD`, `apps/web-platform/infra/` surfaces),
  `scripts/lint-trap-tempfile-ownership.py` (1603 lines, keys on
  `SOLEUR_SCRATCH_SESSION_ROOT` markers), `block-stash-in-worktrees` +
  `block-commit-on-main` (arms inside the 970-line `guardrails.sh` monolith, which
  depends on `lib/incidents.sh` emit machinery).
- `plugins/soleur/skills/constraint-scaffold/` exists: SKILL.md +
  `scripts/constraint-scaffold.sh` + `references/*.template` (6) + `test/*.test.sh` (5).
  ADR-071 (L1 gates) + ADR-074 (two-stage auto-recovery) sanction the
  generate-a-gate-into-user-CI pattern.
- `plugins/soleur/hooks/hooks.json` ships ~8 session hooks (PreToolUse + SessionStart) —
  that is plugin-session delivery, a different surface than repo-CI gates; the generic
  lint corpus is indeed unpackaged.
- No `verification-scaffold` skill exists (`ls plugins/soleur/skills/` — 104 dirs,
  only `constraint-scaffold` matches "scaffold").
- Mechanism/ADR check: grepped `knowledge-base/engineering/architecture/decisions/` for
  scaffold/guardrail-shipping mechanisms; ADR-071/074 are the pattern authority, none
  rejected this shape.
- Verdict: premise holds; hook-count "~121" corrected to 112 files / 55 non-test.

### Property List (Phase 0.6b)

- P1: a durable written audit classifying each `.claude/hooks/*.sh` (non-test) +
  `scripts/lint-*` entry as generic / generic-after-extraction / Soleur-coupled, with
  per-entry rationale (AC1).
- P2: a `verification-scaffold` skill that installs a chosen generic set — minimum
  secret-scan + orphan-test registration + commit-on-main guard — into a user repo's
  hooks and/or CI (AC2).
- P3: scaffolded gates default to advisory/non-blocking where they can block, with a
  documented promotion path (AC3, `wg-dark-launch-deploy-gates`).
- P4: the agent-owns-gates recovery model (ADR-071) carries to emitted artifacts —
  the target user cannot hand-edit a gate.

### Cut List (Phase 0.6b)

- None. M1 (audit doc) is the only mechanism that buys P1; M2 (scaffold skill) is the
  only mechanism that buys P2/P3/P4 — `constraint-scaffold` covers exactly one gate,
  `hooks/hooks.json` covers session hooks not repo CI. No mechanism on `origin/main`
  covers either property.

### Value-Proposition Measurement (Phase 0.6c)

- Not applicable — justification is a user-facing capability gap, not a
  cost/performance saving.

### Repo Research (Phase 1)

- Sibling epic children shipped *references inside existing skills*; #10404 is the one
  child that asks for a NEW skill — a `constraint-scaffold` sibling.
- Skill registration: `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES`
  (name→category map; unregistered falls back to "Uncategorized" — note:
  `constraint-scaffold` itself is unregistered today).
- Skill tests register via `scripts/suite-shard-legs.tsv`, generated by
  `scripts/regenerate-shard-manifest.py --incremental --write`; `lint-orphan-test-suites`
  enforces that every `*.test.sh` is run by a runner (the thing being shipped must not
  orphan its own tests).
- `SKILL_DESCRIPTION_WORD_BUDGET = 2413` in `plugins/soleur/test/components.test.ts`;
  measured baseline **2413/2413 — zero headroom**. A new model-visible skill
  description requires a budget bump (+N words, the file's comment convention).
- `guardrails.sh` arms of interest live at `.claude/hooks/guardrails.sh:130`
  (`block-commit-on-main`), `:471` (`block-stash-in-worktrees`), `:200`
  (`block-recursive-delete`), `:185` (`block-rm-rf-worktrees`).
- Coupling census (grep for SOLEUR_/knowledge-base//plugins/soleur/apps/web-platform/
  doppler/sentry per file): low/zero-coupling hooks — `git-commit-secret-scan.sh` (1),
  `worktree-write-guard.sh` (0), `context-reviewed-gate.sh` (0),
  `memory-backstop-mutation-battery.sh` (0). Zero-coupling lints worth auditing:
  `lint-workflows.sh`, `lint-gh-argv-arg.py`, `lint-workflow-step-env-refs.py`,
  `lint-workflow-issue-write-scope.py`, `lint-workflow-errexit-capture.py`,
  `lint-shell-capture-exit.py`, `lint-dual-lockfile.sh` (3),
  `lint-squash-ci-directives.sh`, `lint-bot-synthetic-*.sh`.

### Institutional Learnings (Phase 1)

- `2026-06-30-constraint-scaffold-verify-every-assumed-capability-at-brand-survival-threshold.md`
  — seven defects, one root cause (assumed-unverified capability): `.github/workflows/`
  only runs at **repo root** in a monorepo (emitted workflow in a subdir is dormant);
  depcruise rc semantics differed from plan; generation path must capture merge-base,
  not working tree; multi-copy drift needs parity tests. The scaffold's emit-target and
  verification model must be designed against this list.
- `2026-10-12-a-global-hook-that-shells-out-inherits-the-project-it-runs-in.md` —
  hooks running in arbitrary user repos treat cwd/env/git-config as attacker-controlled
  input: isolate `GIT_CONFIG_*`, cwd, `HOME`; key persisted state per identity.
- `2026-04-12-hook-paths-must-use-claude-project-dir.md` — hook commands resolve via
  `$CLAUDE_PROJECT_DIR`, never relative paths.
- `2026-07-16-advisory-first-precedent...` + `2026-09-23-arming-an-advisory-gate...` —
  "advisory-first" is a claim to define mechanically (continue-on-error / informational
  exit / non-required check), and promoting an advisory gate to blocking re-reads every
  lenient branch as a bypass: the emitted artifacts must separate "advisory" from
  "weak" so promotion is a one-line flip, not a rewrite.
- `2026-08-01-i-shipped-a-gate-my-own-tests-could-not-see.md` — assertions must anchor
  on constructs a comment cannot produce; deleting the gate must red the suite.
- `2026-05-04-gitleaks-secret-scanning-floor-rollout.md` — gitleaks `secretGroup`
  regex pitfalls; runbook `knowledge-base/engineering/operations/secret-scanning.md`.
- `2026-10-11-sole-copy-pins...` — an advisory guard and its required-check anchor must
  not drift: where a scaffolded repo has both hook (advisory) and CI (blocking later)
  copies of a guard, keep predicate parity or the weaker one certifies the stronger.

### External Research Decision (Phase 1.6)

- Skipped. The guard shapes already exist and are battle-tested in-repo; the novel work
  is extraction/templating/verification against `constraint-scaffold`'s proven pattern,
  not external best practice.

### Functional Overlap (Phase 1.5b)

- Tier-1 hit: `hookify` (anthropics/claude-code) turns conversation instructions into
  warn/block hook rules — LLM-authored rules, not a fixed tested corpus; does not cover
  the AC (curated generic set + CI gates + advisory-first contract). Noted, not adopted.
- `git-hygiene-enforcer` (3★) overlaps partially — Tier 3, discarded per trust model.
- No community artifact covers "install a fixed verified guard set into repo CI".

### Related Issues / PRs

- Epic #10397; siblings #10400 (open), #10401/#10402/#10403 (closed via #10727/#10735/#10738).
- constraint-scaffold lineage: #5765/PR #5770, ADR-071, ADR-074, #5777 amendment.
- `wg-dark-launch-deploy-gates` (AGENTS.rules.md:80) — deploy-gating checks ship
  non-blocking first, observed ≥1 real run before they gate.

### CLAUDE.md / Constitution Conventions Applied

- New skill → register in `docs/_data/skills.js` SKILL_CATEGORIES; SKILL.md +
  optional `scripts/`, `references/`, `test/` dirs; kebab-case; third-person
  description; `--headless` ARGUMENTS convention for non-interactive use.
- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, operator-protection
  signals to stdout.
- Never a `version` key in plugin manifests (delivery mechanism is commit SHA).
- Semver label on PRs touching `plugins/soleur/` (this is `semver:minor` — new skill).

## Problem Statement / Motivation

Soleur applies ~55 non-test hooks and ~40 lint scripts to itself, but ships none of
the *generic* fraction to plugin users. Epic #10397 measured the asymmetry:
`constraint-scaffold` proved a skill can generate a deterministic gate into a user
repo's CI, yet the broader corpus — secret scanning, orphan-test registration,
commit-on-main, stash blocking — stays repo-internal. Users get the pipeline but
not the guardrail depth the pipeline was designed around.

## Proposed Solution

Ship `verification-scaffold`, a `constraint-scaffold` sibling that (a) carries a
written audit of the hook/lint corpus classifying every member as
`generic` / `generic-after-extraction` / `soleur-coupled` with rationale, and
(b) generates the chosen generic set — v1: `secret-scan`, `commit-on-main`,
`block-stash`, `orphan-test` — into a user repo's `.claude/hooks/` +
`.claude/settings.json` (agent surface) and `.github/workflows/` (CI floor),
advisory-first by default with a one-line promotion path.

## Technical Approach

### Architecture

Generator `scripts/verification-scaffold.sh` (POSIX bash, `set -euo pipefail`,
stdout-only operator signals) iterates `references/guards.tsv` — the machine
manifest the audit produces — and emits per-guard templates from
`references/guards/*.template` into the target repo. Flags:
`--target <path>` (default cwd), `--guards <csv>` (default the v1 set),
`--all`, `--mode advisory|enforce` (default `advisory`), `--dry-run`,
`--list`, `--uninstall <guard>`, `--headless` (accepts defaults, no prompts —
constitution headless convention).

Emission contract (mirrors constraint-scaffold): refuse to overwrite any existing
artifact (no `--force`); marker-keyed append-once doc block (`VERIFICATION.md`
created if absent, else a marker block in `README.md`); `.claude/settings.json`
merged via `jq` — created if absent, malformed JSON refused pre-write, hook
entries deduped on their `command` string; workflows land at **repo root**
`.github/workflows/` (monorepo lesson: subdir workflows are dormant); a `mkdir`
lock in the git common dir serializes concurrent runs; a TMPDIR-detached-worktree
bite-proof proves every installed guard pass→fail→pass before the doc block is
written; a pre-first-write armed trap restores the tree on any failure (exit-site
table in the Guard Contract).

### Emitted artifacts (per guard)

| Guard | Hook surface (`.claude/hooks/` + settings.json) | CI surface (`.github/workflows/verification-gates.yml` jobs) | Aux artifacts |
|---|---|---|---|
| `secret-scan` | PreToolUse `git commit` gate → gitleaks staged scan; advisory: warn+allow→`ask` on finding; enforce: deny | `gitleaks git --pre-commit`-style job on PRs, `continue-on-error: true` in advisory | `.gitleaks.toml` emitted only when absent (default-ruleset pointer; never overwrites a user's ruleset) |
| `commit-on-main` | PreToolUse `git commit` → emitted `precommit-guard.sh` (near-verbatim emit of `plugins/soleur/scripts/precommit-guard.sh` + `lib/wrapper-boundary.sh`); advisory: warn+allow; enforce: deny | none (a local-commit concern; README documents branch protection as the remote floor) | `scripts/verification/precommit-guard.sh`, `scripts/verification/lib/wrapper-boundary.sh` |
| `block-stash` | PreToolUse gate on `git stash` (boundary-prefixed regex); advisory: warn+allow; enforce: deny | none | — |
| `orphan-test` | none (a lint, not a command gate) | `orphan-test` job: `scripts/verification/orphan-test-check.sh` — `git ls-files '*.test.sh'` must each be named in ≥1 registration surface: any `.github/workflows/*.{yml,yaml}`, any file matched by user-declared runner globs (`scripts/test-all.sh`, `scripts/run-tests*`, `Makefile`, `package.json` — declared in `verification-gates.yml` env), or the exclusion manifest `.github/verification-known-orphans.txt` (reason-required per line) | `scripts/verification/orphan-test-check.sh`, seed manifest |

### Advisory-first contract

Advisory is a *decision-verb* difference, never a detection difference: every
emitted guard runs identical predicates in both modes; only the terminal decision
changes (warn+allow / `ask` / non-blocking job vs deny / failing job). The
emitted README names the promotion step per artifact — flip `MODE=` in the hook,
drop `continue-on-error`, add the check to required status checks — and requires
≥1 observed clean run first (per `wg-dark-launch-deploy-gates`). Promotion
re-reads every lenient branch as a bypass (`2026-09-23` learning), so the
templates carry NO advisory-only skip arms: a missing gitleaks in advisory mode
warns-and-allows loudly; in enforce mode it denies with the install remediation.
Emitted guards are local-only: zero network egress, findings redacted
(`--redact`), nothing transmitted.

### Templates, not copies

Every corpus member carries Soleur couplings (`lib/hook-input.sh`,
`emit_incident`, KB pointers, `TEST_GROUP`/`SCRIPTS_SHARD`). Templates are
self-contained single files — no lib sourcing, jq optional-with-degradation,
no KB citations in emitted runtime text (provenance lives in comments +
`guards.tsv`, never in user-facing output). The one near-verbatim emit is
`precommit-guard.sh` + `wrapper-boundary.sh`, already designed self-contained;
a repo test byte-pins template↔source.

### Implementation Phases

#### Phase 1 — Audit + manifest

Walk `.claude/hooks/*.sh` (non-test) + `scripts/lint-*` (excluding `.test.sh`,
`.baseline.txt`, `.highwater`): classify each `generic` /
`generic-after-extraction` / `soleur-coupled` with one-line rationale citing its
couplings. Emit `references/guardrail-audit.md` (human doc) and
`references/guards.tsv` (columns: name, verdict, surfaces, template, default
mode, deps, source_files, v1|v2). The v1 set per CTO ruling 4; `block-rm-rf`
promoted to v1 only if the audit confirms a self-contained arm.

#### Phase 2 — Templates + docs

Author `references/guards/*.template` (self-contained generic variants),
`references/verification-readme.template`, `references/gitleaks.toml.template`.

#### Phase 3 — Generator

`scripts/verification-scaffold.sh`: flag parsing, guards.tsv iteration, emit +
settings.json merge + workflow emit + doc block, TMPDIR bite-proof, trap-based
self-cleanup, lock, `--uninstall`, `--dry-run`, `--list`.

#### Phase 4 — Tests, registration, docs

`test/generator.test.sh` (flags, refusals, idempotent re-run, settings merge,
mode flips), `test/bite-proof.test.sh` (per-guard pass→fail→pass on fixture
repo), `test/manifest.test.sh` (every guards.tsv v1 row has a template + audit
entry; every audit corpus member appears — census over the live tree, not a
pinned list; `precommit-guard.sh` template↔source byte-parity). Registrations:
`docs/_data/skills.js` (`"verification-scaffold": "Workflow"`), cursor stub via
`sync-cursor-name-map.ts`, `components.test.ts` budget bump, shard manifest
regen, README 103→104, content-strategy entry.

## Alternative Approaches Considered

| Option | Why rejected |
|---|---|
| Ship guards via `hooks/hooks.json` (plugin session hooks) | Session hooks guard the user's agent sessions but not their CI, and give no per-repo opt-in, no audit artifact, no advisory→enforce lifecycle. The issue asks for repo-installed gates. |
| Extend `constraint-scaffold` in place | It emits exactly one gate with a Next.js precondition; a multi-guard corpus is a different skill contract (guards.tsv, per-guard modes, hook+CI dual surface). Sibling, not extension. |
| Verbatim-vendor the repo hook/lint files | Every candidate carries Soleur couplings that dead-reference in a user repo (census in Research Insights). Templates are the honest generalization. |
| Two PRs (audit, then scaffold) | CTO ruling 1: the audit's only consumer is the scaffold; split leaves an unactioned artifact and splits one design decision across two reviews. Escape hatch recorded in decision-challenges.md if the audit balloons. |
| Emit lefthook/pre-commit framework config instead of Claude hooks | Claude Code hooks are the surface the plugin user's agents actually hit; lefthook is a repo-toolchain assumption the scaffold cannot make. CI workflow covers the non-agent floor. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a half-installed guard set in
  their repo (untracked scripts, a settings.json hook entry pointing at a
  missing file, a workflow that reds every PR) — or worse, a silently inert
  guard the user believes protects them (the emitted `secret-scan` that never
  runs because `.gitleaks.toml` was never emitted).
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  shipped secret-scan template whose ruleset is weaker than the repo source
  lets a credential land in the user's git history — a data exposure the user
  adopted Soleur precisely to prevent; a settings.json merge that corrupts the
  file wedges every hook the user already had (workflow exposure).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the deliverable writes executable
  gates into a mutable user surface — a single bad emit is a single user's CI
  or credential; it is not bounded to prose quality (as #10403 was), so `none`
  and `aggregate pattern` are both wrong.

*CPO sign-off required at plan time (`requires_cpo_signoff: true`); CPO
assessment ran in-process at Phase 2.5 — operator countersignature recorded as a
decision-challenges row for `ship` to render.*
`soleur:engineering:review:user-impact-reviewer` runs at review time per the
sign-off lifecycle.

## Architecture Decision (ADR/C4)

### ADR

- New ADR (**provisional ADR-295** — next free on this branch; a sibling may
  claim it, `adr-ordinals` CI + ship Phase 5.5 re-verify): "Ship the generic
  guardrail corpus via template emission into user-repo hooks + CI". Records:
  dual-surface delivery, advisory-first mode contract, template-over-vendoring,
  guards.tsv manifest, and that `precommit-guard.sh` is the sole near-verbatim
  emit. Amends nothing; ADR-071/074 are cited as precedent, not superseded.

### C4 views

- **Component view** (`model.c4` + `views.c4`): add `verificationscaffold`
  component beside `constraintscaffold` in the plugin system — "Generates the
  generic guardrail set (secret-scan, commit-on-main, block-stash, orphan-test)
  into a user repo's hooks and CI, advisory-first" — plus its `view … include`
  line where `constraintscaffold` is included (views.c4:111 region). C4
  completeness check performed: external actors (plugin user — already modeled
  as the operator/founder elements), external systems (GitHub Actions runner —
  modeled; gitleaks binary — a local tool, not a system element), containers
  touched (plugin system — already present), access relationships (plugin →
  user repo write surface — already asserted by the `emit-decision.sh` /
  `lint-ratchet.py` write-surface prose in the plugin description). New element
  needed: the component itself only. Run `c4-code-syntax.test.ts` +
  `c4-render.test.ts` after editing.

### Sequencing

ADR authored in this PR describing the shipped state (status: active); no soak
gate applies.

## Files to Create

- `plugins/soleur/skills/verification-scaffold/SKILL.md`
- `plugins/soleur/skills/verification-scaffold/scripts/verification-scaffold.sh`
- `plugins/soleur/skills/verification-scaffold/references/guardrail-audit.md`
- `plugins/soleur/skills/verification-scaffold/references/guards.tsv`
- `plugins/soleur/skills/verification-scaffold/references/verification-readme.template`
- `plugins/soleur/skills/verification-scaffold/references/gitleaks.toml.template`
- `plugins/soleur/skills/verification-scaffold/references/guards/secret-scan-hook.sh.template`
- `plugins/soleur/skills/verification-scaffold/references/guards/commit-on-main-hook.sh.template`
- `plugins/soleur/skills/verification-scaffold/references/guards/precommit-guard.sh.template`
- `plugins/soleur/skills/verification-scaffold/references/guards/wrapper-boundary.sh.template`
- `plugins/soleur/skills/verification-scaffold/references/guards/block-stash-hook.sh.template`
- `plugins/soleur/skills/verification-scaffold/references/guards/orphan-test-check.sh.template`
- `plugins/soleur/skills/verification-scaffold/references/guards/verification-gates.yml.template`
- `plugins/soleur/skills/verification-scaffold/test/generator.test.sh`
- `plugins/soleur/skills/verification-scaffold/test/bite-proof.test.sh`
- `plugins/soleur/skills/verification-scaffold/test/manifest.test.sh`
- `plugins/soleur/cursor/skills/soleur-verification-scaffold/SKILL.md` (generated by `sync-cursor-name-map.ts`)
- `knowledge-base/engineering/architecture/decisions/ADR-295-*.md` (provisional ordinal)

## Files to Edit

- `plugins/soleur/docs/_data/skills.js` — `"verification-scaffold": "Workflow"` in `SKILL_CATEGORIES`
- `plugins/soleur/test/components.test.ts` — `SKILL_DESCRIPTION_WORD_BUDGET` bump (+~20 words, comment convention)
- `scripts/suite-shard-legs.tsv` — `regenerate-shard-manifest.py --incremental --write`
- `plugins/soleur/README.md` — skills count 103 → 104
- `knowledge-base/marketing/content-strategy.md` — one entry (sibling-PR pattern)
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4` — `verificationscaffold` component + include

## Implementation Phases

See `### Implementation Phases` under Technical Approach (audit → templates →
generator → tests/registration/docs). Sequencing constraint: Phase 1's
`guards.tsv` is the data spine for everything after it; Phase 4's manifest test
is what keeps audit ↔ manifest ↔ templates consistent.

## Open Code-Review Overlap

3 open code-review issues touch planned paths; all acknowledged, none folded:

- `#8593` (components.test.ts probe-gate scope-out) — **acknowledge**: unrelated
  to the budget-constant bump; its own cycle.
- `#10240`, `#3649` (content-strategy.md marketing scope-outs) — **acknowledge**:
  one-line entry added here; their campaigns are independent.
- `#8800` (lint-orphan-test-suites fixture census) — **acknowledge**: the audit
  *reads* that script but no edit is planned; the emitted orphan-test guard is a
  new template, not a port of the file the scope-out concerns.

Query: `gh issue list --label code-review --state open --limit 200` (95 issues),
jq `contains($path)` per planned path, 2026-10-21.

## Observability

The shipped surface is a generator plus emitted guards; the observability
questions are (a) does the skill stay registered/wired in the plugin, (b) do the
manifest↔audit↔template links stay consistent, (c) does the emitted contract
stay honest (advisory-by-default, no egress).

```yaml
liveness_signal:
  what: "verification-scaffold skill registered (skills.js + cursor stub + README count) and manifest/audit/template triad consistent (manifest.test.sh census)"
  cadence: "per-PR: components.test.ts + suite shard legs; manifest.test.sh in scripts shard"
  alert_target: "CI check failure (plugin test shard)"
  configured_in: "plugins/soleur/test/components.test.ts; plugins/soleur/skills/verification-scaffold/test/manifest.test.sh"
error_reporting:
  destination: "CI job log — census failure names the unmanifested guard/template/orphan audit row"
  fail_loud: "yes — registration and manifest drift are suite failures"
failure_modes:
  - mode: "a guards.tsv row without a template (or a template no row names)"
    detection: "manifest.test.sh census"
    alert_route: "CI red on the diff that created the orphan"
  - mode: "a new .claude/hooks or scripts/lint-* member unclassified by the audit"
    detection: "manifest.test.sh corpus census (git ls-files driven, not a name list)"
    alert_route: "CI red"
  - mode: "emitted guard defaults drift to blocking (advisory contract broken)"
    detection: "generator.test.sh mode assertions + emitted-fixture grep for continue-on-error / MODE="
    alert_route: "CI red"
  - mode: "template acquires a Soleur coupling or network egress"
    detection: "manifest.test.sh emitted-content grep: zero hits for knowledge-base/|SOLEUR_|plugins/soleur in emitted runtime text; zero curl|wget|https?:// outside comments"
    alert_route: "CI red"
logs:
  where: "CI job log (suite assertion lines)"
  retention: "GitHub Actions retention"
discoverability_test:
  command: "grep -q 'verification-scaffold' plugins/soleur/docs/_data/skills.js && grep -q 'secret-scan' plugins/soleur/skills/verification-scaffold/references/guards.tsv && echo verification-wired"
  expected_output: "verification-wired"
```

## Guard Contract

The deliverable IS guards. Entries below are written against the design; the
implementation test suites instantiate them.

### Guard 1 — emitted `secret-scan` (hook + CI job)

**Property.** A `git commit` (hook) or PR push (CI) whose staged/diff content
contains a secret-shaped string is reported; in enforce mode it is denied, in
advisory mode it surfaces as `ask` (hook) or a visible non-blocking failure
(CI).

**Assembly.** Emitted `.claude/hooks/secret-scan.sh` registered in the user's
`.claude/settings.json` `hooks.PreToolUse` (matcher `git commit` commands —
chokepoint: the settings.json hook registry entry, the single registration
point the generator owns); emitted `gitleaks` job in
`.github/workflows/verification-gates.yml` (chokepoint: the workflow's job
block); `.gitleaks.toml` at repo root (emitted only when absent — never
overwrites an existing ruleset).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Bite-proof injects a secret-shaped string into a staged fixture file | RED — hook reports (advisory: `ask`; enforce: deny) and CI job fails |
| 2 | Hook's gitleaks invocation neutered (scanner exits 0 without scanning — empty report treated as clean) | RED — bite-proof arm asserts a finding was produced, not just rc==0; the guard's own dispatch is suspect when "0 checked" |
| 3 | A SECOND staged file carrying a secret after a clean first file | RED — scan must cover the whole index, not first match |
| 4 | Harness: fixture gitleaks stub always reports clean | RED — suite must fail, proving the fixture asserts on real signal |
| 5 | Must-PASS: a `gitleaks:allow`-annotated known-safe fixture commits | PASS — advisory or enforce, no report |
| 6 | Same diff weakens emitted `.gitleaks.toml` rules AND the fixture set | RED — anchor: manifest.test.sh byte-pins the template's rule count to `guards.tsv` `deps` column; a ruleset weaker than declared cannot pass |

### Guard 2 — emitted `commit-on-main` (hook only)

**Property.** No `git commit` executes against a default-branch checkout without
a decision: deny in enforce, warn+allow in advisory.

**Assembly.** Emitted `.claude/hooks/commit-on-main.sh` (settings.json
chokepoint as Guard 1) → emitted `scripts/verification/precommit-guard.sh`
+ `lib/wrapper-boundary.sh` (the detector, near-verbatim emit);
`.claude/settings.json` registration (same chokepoint).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Fixture repo checked out on `main`, stdin payload `{"tool_input":{"command":"git commit -m x"}}` | RED — deny (enforce) / warn+allow (advisory) per mode |
| 2 | settings.json hook entry deleted while script remains (registration severed) | RED — generator bite-proof asserts the registration, not just the file; `generator.test.sh` asserts idempotent re-registration dedupes on command string |
| 3 | `cd repo && git commit` chained payload (second member after a bare `git commit`) | RED — boundary-prefixed detection covers chain operators |
| 4 | Harness: payload fixture `git commit` on a `feat-x` branch | PASS — must-PASS input differing from canonical main; proves the guard is not deny-everything |
| 5 | Same diff weakens `precommit-guard.sh` detection AND the emitted template | RED — anchor: `manifest.test.sh` byte-parity `cmp` of template vs `plugins/soleur/scripts/precommit-guard.sh` catches drift, and the fixture battery catches a weakened detector on BOTH sides of the parity |

### Guard 3 — emitted `block-stash` (hook only)

**Property.** No `git stash` command (any chain position) passes the hook
undecided.

**Assembly.** Emitted `.claude/hooks/block-stash.sh` + settings.json
registration (same chokepoint as Guards 1–2).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | stdin payload `git stash` | RED — deny (enforce) / warn+allow (advisory) |
| 2 | `git add x && git stash pop` (stash not leading) | RED — chain-boundary regex, not `^`-anchored |
| 3 | Registration removed (hook unregistered in settings.json) | RED — bite-proof asserts registry entry presence |
| 4 | Must-PASS: `git stash list` documented-exception payload or `git status` | PASS — non-stash-mutating command flows through |

### Guard 4 — emitted `orphan-test` (CI job + runner script)

**Property.** Every `git ls-files '*.test.sh'` in the target repo is referenced
by ≥1 declared registration surface — a workflow file, a declared runner glob,
or a reason-carrying exclusion-manifest line.

**Assembly.** Emitted `scripts/verification/orphan-test-check.sh` invoked by the
`orphan-test` job in `verification-gates.yml` (chokepoint: the job's run line);
registration surfaces declared in the job env (`RUNNER_GLOBS`) +
`.github/verification-known-orphans.txt`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Bite-proof adds `scratch.test.sh` referenced by nothing | RED — orphan reported by path |
| 2 | A suite's only registration reference deleted (runner line removed) | RED — re-derives orphans, doesn't trust a stale allow-list |
| 3 | `RUNNER_GLOBS` narrowed so zero files match (guard's own dispatch — "0 checked" exits 0) | RED — the check fails loudly when its producer enumerates nothing |
| 4 | TWO orphan suites added | RED — both named, not just the first |
| 5 | Must-PASS: an orphan listed in `verification-known-orphans.txt` WITH a reason suffix | PASS — exclusion manifest is a recorded decision, not silent absorption |

### Guard 5 — generator emit-safety (the install window)

**Property.** Every failure after the first emitted write leaves the user tree
as found; no failure leaves a partial install.

**Assembly.** All emit sites in `verification-scaffold.sh` ordered: templates →
scripts → `.gitleaks.toml` → settings.json merge → workflow → [bite-proof] →
doc block last; trap armed before the FIRST write and disarmed after the
bite-proof passes. Exit-site table (position relative to first write): pre-write
refusals (missing target, malformed settings.json, TMPDIR-inside-repo, existing
artifact collision, lock held) write nothing; mid-write failures (any emit rc≠0,
INT/TERM, set -e abort) trigger the trap; post-bite failures (doc-block write)
warn only — the install is proven by then.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `kill -TERM` after the second emitted file | tree identical to pre-install (`git status` clean of untracked emits) |
| 2 | settings.json malformed at install time | refusal BEFORE any write; file untouched |
| 3 | second `--guards` run after a successful first (existing artifacts) | refusal, zero writes — no overwrite path exists |
| 4 | TMPDIR resolving inside the target repo | refusal pre-write (constraint-scaffold exit-69 precedent) |
| 5 | Must-PASS: `--uninstall secret-scan` on a clean install | removes only that guard's artifacts + settings entry, leaves siblings |

### Guard 6 — advisory-mode contract (cross-cutting)

**Property.** A default install cannot block a commit or a PR; `--mode enforce`
flips only the decision verb, never the detection predicate.

**Assembly.** `MODE=` line in each emitted hook + `continue-on-error: true` in
each emitted CI job (chokepoints: per-template mode lines, the workflow job
block).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Default-install fixture: secret-scan hook fed a secret payload | reports + `ask`, never a silent `allow` and never a `deny` |
| 2 | `--mode enforce` install: same payload | `deny` |
| 3 | `--mode bogus` | install refuses pre-write (fail-closed flag validation) |
| 4 | CI job emitted without `continue-on-error` in advisory mode | RED — `generator.test.sh` asserts the advisory markers on the emitted fixture, not the template text |
| 5 | Must-PASS: emitted README promotion paragraph present in both modes | PASS — promotion path documented regardless of installed mode |

## SpecFlow Findings (Phase 3, in-process)

Flow-walk of the install/promote/uninstall journeys produced seven resolutions,
each bound to an implementation site (paper-resolution lint — no orphan FRs):

1. **Default-branch detection.** The emitted commit-on-main guard must not
   hardcode `main|master`: `verification-scaffold.sh` resolves the target's
   default via `git symbolic-ref refs/remotes/origin/HEAD` (fallback
   `main|master`) and stamps it into the emitted `precommit-guard.sh` config
   line. Covers `trunk`/custom defaults.
2. **Target precondition.** Target must be a git work tree (`git rev-parse
   --is-inside-work-tree`); non-repo targets refuse pre-write — the git-common-
   dir lock requires git anyway. Same class as constraint-scaffold's
   precondition (exit 65).
3. **Directory creation.** `.claude/hooks/`, `.github/workflows/`,
   `scripts/verification/` are created when absent — documented emit behavior,
   removed by `--uninstall` only if the run created them AND they're empty.
4. **CI gitleaks provisioning.** Emitted workflow uses
   `gitleaks/gitleaks-action` **pinned by commit SHA** (supply-chain posture —
   a curl-installed binary would be an unpinned executable fetch); the README
   documents the pin and the version it resolves to.
5. **`--uninstall` idempotent.** On a never-installed guard: prints "not
   installed", lists installed guards, exit 0.
6. **Advisory `ask` scope.** The emitted secret-scan returns `ask` ONLY on real
   gitleaks findings (high-signal, rare); scanner errors/missing binary →
   warn+allow (advisory) / deny+remediation (enforce). An `ask` can never fire
   on tool-error in any mode.
7. **POSIX-only.** Emitted guards require bash+POSIX tools (stated in SKILL.md
   and emitted README); no Windows surface in v1.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A written audit list: which hooks/lints are generic vs Soleur-coupled, with rationale." | `references/guardrail-audit.md` + `references/guards.tsv` (Phase 1) | mapped |
| 2 | "Users can scaffold at least the secret-scan + orphan-test + commit-guard set into their own repo." | the skill + `verification-scaffold.sh` + guard templates + settings/workflow emit (Phases 2–3) | mapped |
| 3 | "Shipped gates are advisory-first per `wg-dark-launch-deploy-gates` where they can block." | advisory-first mode contract (Guard 6) + `continue-on-error` CI + warn/ask hook defaults | mapped |
| 4 | "audit the 121 hooks + `scripts/lint-*` for entries that are repo-generic (no Soleur-domain coupling)" | Phase 1 audit — census over `.claude/hooks/*.sh` non-test + `scripts/lint-*`, count corrected to 112/55 | mapped |
| 5 | "a `verification-scaffold` skill (constraint-scaffold sibling) that installs the chosen generic set into a user repo's hooks/CI" | `plugins/soleur/skills/verification-scaffold/` — dual-surface generator | mapped |

### Plan-Item Provenance

| Plan item | User words cited | Verdict |
|-----------|------------------|---------|
| `references/guardrail-audit.md` | "A written audit list: which hooks/lints are generic vs Soleur-coupled, with rationale." | asked |
| `references/guards.tsv` | "installs the chosen generic set" — the manifest IS the chosen set | inferred — justification: machine-readable form the generator iterates; the audit doc alone is prose a script cannot consume |
| `scripts/verification-scaffold.sh` + `references/guards/*.template` | "a `verification-scaffold` skill … that installs the chosen generic set into a user repo's hooks/CI" | asked |
| `verification-gates.yml.template` | "into a user repo's hooks/CI" | asked |
| `gitleaks.toml.template` | "secret-scan" — the repo's own guard fails open without it; emitting no config ships a vacuous guard | inferred — justification: a secret-scan that never scans is the vacuous-guard class the Guard Contract exists to prevent |
| `test/*.test.sh` ×3 | constraint-scaffold precedent + lint-orphan-test-suites (every new suite must be registered) | inferred — justification: a guard whose failure mode is "silently stops detecting" needs a companion suite (repo convention, enforced) |
| `cursor/skills/soleur-verification-scaffold/SKILL.md` | — | inferred — justification: cursor-name-map harness parity; missing stub fails `cursor-name-map.test.ts` |
| `docs/_data/skills.js` entry | — | inferred — justification: constitution "manually register it in SKILL_CATEGORIES … silently omit unregistered skills" |
| `components.test.ts` budget bump | — | inferred — justification: zero headroom measured (2413/2413); the enforcing gate |
| `suite-shard-legs.tsv` regen | — | inferred — justification: new test files need shard legs or lint-orphan-test-suites reds |
| `README.md` 103→104 | — | inferred — justification: pre-commit component-count verification |
| `content-strategy.md` entry | — | inferred — justification: sibling epic children all carried it (#10727/#10735/#10738) |
| ADR-295 + `model.c4`/`views.c4` edit | — | inferred — justification: plan Phase 2.10 — new user-repo write surface is an architectural decision; deferral is a reject condition |

### Split Assessment

- Subsystems touched: 3 — `plugins/soleur`, `scripts`, `knowledge-base`
- Planned files: ~24 | Estimated changed lines: ~3,200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — `references/guardrail-audit.md`+`guards.tsv` vs the
  rest — **overridden**: CTO ruling 1 (decision-challenges.md) keeps audit +
  scaffold in one PR; the audit's only consumer is the scaffold and sibling
  children all landed single PRs. Escape hatch: if the audit exceeds ~500 lines
  of per-entry rationale, split it per the recorded dissent.

## Acceptance Criteria

- [ ] AC1: `references/guardrail-audit.md` classifies EVERY `.claude/hooks/*.sh`
  non-test file + `scripts/lint-*` (excluding `.test.sh`/`.baseline.txt`/`.highwater`)
  as `generic` / `generic-after-extraction` / `soleur-coupled` with a one-line
  rationale; `manifest.test.sh` drives the corpus from `git ls-files` so a new
  member missing a classification reds CI.
- [ ] AC2: `bash verification-scaffold.sh --target <fixture> --headless` installs
  the v1 set (secret-scan, commit-on-main, block-stash, orphan-test): emitted
  files present at fixture-relative paths, settings.json hook entries
  registered, `verification-gates.yml` at repo root.
- [ ] AC3: On the default (advisory) install, every emitted CI job carries
  `continue-on-error: true` and every emitted hook warns/asks instead of
  denying; `--mode enforce` produces deny-decisions; emitted README documents
  the promotion step per artifact.
- [ ] AC4: Bite-proof on the fixture repo: each installed guard passes clean →
  fails on an injected violation → passes after revert, per-guard, with logs.
- [ ] AC5: Non-destructive: pre-existing `.gitleaks.toml`, settings.json,
  workflow, or hook file causes refusal with zero writes; second full run
  refuses; `--uninstall <guard>` removes only that guard's artifacts.
- [ ] AC6: Self-cleanup: a TERM/failure after first write but before bite-proof
  completion leaves `git status` identical to pre-install.
- [ ] AC7: settings.json merge: absent file created; existing file preserves
  unrelated entries; malformed JSON refused pre-write; re-run dedupes (no
  double hook entries).
- [ ] AC8: Emitted-content hygiene: zero `SOLEUR_`/`knowledge-base/`/
  `plugins/soleur` references in emitted runtime text; zero network egress
  tokens (`curl|wget|https?://`) outside comments in emitted artifacts.
- [ ] AC9: Registrations green: `components.test.ts` (budget bump), cursor stub
  exists (`cursor-name-map.test.ts`), skills.js entry, `suite-shard-legs.tsv`
  regenerated (new suites have legs), README skills count = 104.
- [ ] AC10: `ADR-295-*.md` (or renumbered ordinal) exists; `model.c4` +
  `views.c4` carry `verificationscaffold`; `c4-code-syntax.test.ts` +
  `c4-render.test.ts` pass.
- [ ] AC11: `manifest.test.sh` byte-parity:
  `precommit-guard.sh.template` == `plugins/soleur/scripts/precommit-guard.sh`
  (and `wrapper-boundary` pair), so the canonical source and the emit cannot
  drift silently.
- [ ] AC12: PR carries `semver:minor` label + `## Changelog` section
  (`plugins/soleur/` touched).

## Domain Review

**Domains relevant:** engineering, product, marketing

### Engineering

**Status:** reviewed (in-process, CTO Rule interface — headless pipeline)
**Assessment:** nine rulings recorded in
`knowledge-base/project/specs/feat-one-shot-10404-verification-scaffold/decision-challenges.md`:
single-PR, dual-surface delivery, mode-flag advisory mechanics, v1 guard set,
templates-over-vendoring, audit+manifest co-location, per-guard bite-proof,
single-user-incident threshold.

### Product/UX Gate

**Tier:** none — no UI-surface files in Files to Create/Edit (all
`.sh`/`.md`/`.yml`/`.tsv`/`.c4`); mechanical override does not fire.
**Decision:** auto-accepted (pipeline) — CPO assessment ran in-process:
user-facing capability requiring simple invocation + legible emitted docs +
documented uninstall; spec-flow-analyzer delegated for Phase 3 flow validation.
**Agents invoked:** soleur:product:cpo (in-process assessment)
**Skipped specialists:** soleur:product:design:ux-design-lead (no UI surface —
non-skippable rule does not apply), soleur:marketing:copywriter (no marketing
copy surface; emitted README is technical reference)
**Pencil available:** N/A (no UI surface)

### Marketing

**Status:** reviewed (in-process, CMO role)
**Assessment:** new user-facing capability = content amplification opportunity;
matches the "taste compounds" positioning. One `content-strategy.md` entry
(sibling-PR pattern); no copywriter needed (no landing/email/social surface).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- `unit` Given fixture repo with clean tree, when generator runs `--headless`,
  then all v1 artifacts exist at fixture-relative paths + settings.json
  registered + workflow at repo root.
- `unit` Given fixture carrying a real `.gitleaks.toml`, when generator runs,
  then refusal pre-write (no overwrite) — AC5.
- `unit` Given malformed `.claude/settings.json`, when generator runs, then
  refusal before any write — AC7.
- `unit` Given a first successful install, when re-run, then refusal + zero
  writes; when `--uninstall block-stash`, then only that guard's artifacts +
  settings entry removed — AC5.
- `integration` Given installed advisory fixture, when hook stdin carries a
  secret-shaped staged file, then `ask` decision + redacted finding; when
  `--mode enforce` install, then `deny` — AC3/Guard 6.
- `integration` Given installed fixture, when a scratch `x.test.sh` is
  committed unregistered, then `orphan-test-check.sh` names it by path; when
  added to `verification-known-orphans.txt` with a reason, then clean —
  AC4/Guard 4.
- `integration` Given bite-proof run, when `kill -TERM` lands after second
  emit, then `git status` identical to pre-install — AC6.
- `unit` Given `git ls-files` corpus enumeration, when a new
  `.claude/hooks/x.sh` lacks an audit row, then `manifest.test.sh` reds — AC1.
- `unit` Given the emitted artifact set, when grepped for
  `SOLEUR_|knowledge-base/|curl|wget|https://`, then zero runtime hits — AC8.

### Regression / Edge Cases

- `git commit` inside `cd <dir> &&` chains and env-assignment prefixes are
  detected (wrapper-boundary grammar parity with the canonical source).
- A user repo on `master` (not `main`) default branch is honored — the
  commit-guard's default-branch set is not Soleur-specific.
- `gitleaks` absent on the user's PATH: hook warns-and-allows (advisory) /
  denies-with-remediation (enforce); CI job installs or skips per its declared
  posture — never a silent clean.
- `--dry-run` writes nothing and prints the full emit plan.
- A monorepo target: workflow still lands at repo root (subdir workflows are
  dormant — constraint-scaffold defect 5).

## Success Metrics

- `gh issue view 10404` AC bullets mechanically satisfied (audit doc exists +
  census-enforced; v1 set scaffolds; advisory default).
- `manifest.test.sh` + `generator.test.sh` + `bite-proof.test.sh` green in the
  scripts shard.
- Zero regressions: components.test.ts, cursor-name-map.test.ts,
  lint-orphan-test-suites.sh all green post-registration.

## Dependencies & Prerequisites

- `jq` at generator runtime for settings.json merge — degrade: refuse hook
  registration with a named remediation rather than corrupt the file (CI legs
  still emit).
- `gitleaks` on the user's PATH for the emitted secret-scan hook; the CI job
  pins a version (`GL_REMEDIATION` precedent: 8.24.x).
- `git` worktree support for the bite-proof's detached TMPDIR staging.
- No new runtime dependencies added to the repo (constitution: no dependency an
  LLM can generate inline).

## Risk Analysis & Mitigation

- **Risk: emitted guards drift from repo sources.** Mitigation: templates are
  the shipped form (the repo versions are NOT their source of truth at
  runtime); `manifest.test.sh` byte-parity on the one verbatim pair;
  guards.tsv provenance column.
- **Risk: settings.json merge corrupts a user's config.** Mitigation:
  jq-parse-then-write, refuse on malformed input pre-write, dedupe on command
  string, trap-restored on any post-merge failure.
- **Risk: advisory defaults become permanent weak guards.** Mitigation: emitted
  README names the promotion step + ≥1-clean-run precondition per
  `wg-dark-launch-deploy-gates`; promotion is a one-line flip by design.
- **Risk: the audit rots as the corpus grows.** Mitigation: census-driven
  `manifest.test.sh` — a new unclassified corpus member reds CI (the audit is
  enforced, not aspirational).
- **Risk: hook surface unusable on non-Claude harnesses.** Mitigation:
  documented — hooks serve Claude-Code-compatible `.claude/` consumers; CI
  serves everyone else; both emitted together so no cohort is floorless.

## Resource Requirements

- ~1 day audit (issue estimate) + generator/templates/tests comparable to a
  constraint-scaffold-sized change; single-PR per CTO ruling.

## Future Considerations

- v2 candidates the audit marks `generic-after-extraction` (e.g.
  `lint-trap-tempfile-ownership`, `lint-workflows.*`, `lint-gh-argv-arg`,
  `lint-dual-lockfile`, `block-rm-rf`, `worktree-write-guard`,
  `memory-backstop-mutation-battery` core) — add = one guards.tsv row +
  template + audit row.
- `soleur-coupled` members stay repo-internal by design; the audit doc is the
  record of why.
- Non-goals carried below stay non-goals until a follow-up issue re-scopes.

## Non-Goals

- Porting the full ~40-lint corpus or the `guardrails.sh` monolith wholesale —
  Soleur-coupled by the census; v2 candidates only where the audit says
  `generic-after-extraction`.
- Auto-recovery (ADR-074-style two-stage dispatcher) for emitted gates —
  v1 gates are advisory; a stuck founder can delete the artifacts.
- `lefthook`/pre-commit-framework emission — wrong toolchain assumption.
- `--force`/overwrite semantics — refusal is the contract.
- The pre-existing `flag-bootstrap/` SKILL.md absence — observed, out of scope.

## Documentation Plan

- `SKILL.md` (usage, modes, emitted-artifact table, agent-owns-gates model).
- Emitted `VERIFICATION.md`/README block in the target repo (what's installed,
  advisory→enforce promotion, uninstall).
- `references/guardrail-audit.md` ships with the skill — the corpus rationale
  is user-visible documentation.
- ADR-295 (provisional) + C4 component.

## References & Research

### Internal References

- Pattern authority: `plugins/soleur/skills/constraint-scaffold/` (SKILL.md,
  `scripts/constraint-scaffold.sh`, `test/parity.test.sh`); ADR-071, ADR-074.
- Canonical emit: `plugins/soleur/scripts/precommit-guard.sh` +
  `scripts/lib/wrapper-boundary.sh` (self-contained by design).
- Repo sources per guard: `.claude/hooks/git-commit-secret-scan.sh`,
  `guardrails.sh` arms (`block-commit-on-main`:130, `block-stash-in-worktrees`:471),
  `scripts/lint-orphan-test-suites.sh`.
- Learnings cited in Research Insights (constraint-scaffold capability
  verification, global-hook env isolation, CLAUDE_PROJECT_DIR, advisory-first
  mechanics, assertion anchoring, gitleaks rollout, sole-copy predicate parity).

### Related Work

- Epic #10397; siblings #10400–#10403 (closed: PRs #10727/#10735/#10738).
- constraint-scaffold: #5765/PR #5770, #5777 amendment, #8288.
