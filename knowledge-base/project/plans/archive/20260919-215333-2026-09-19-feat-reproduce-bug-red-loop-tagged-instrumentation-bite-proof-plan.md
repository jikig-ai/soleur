---
title: "feat(reproduce-bug): red-capable loop gate, tagged instrumentation, seam-absence finding"
date: 2026-09-19
slug: feat-reproduce-bug-red-loop-tagged-instrumentation-bite-proof
branch: feat-one-shot-8288-reproduce-bug-red-loop
issue: 8288
closes: 8288
type: feature
lane: cross-domain
domain: engineering
priority: p1-high
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

No `spec.md` existed for this branch when planning began, so `lane:` could not be carried forward and is set to `cross-domain` (TR2 fail-closed). That is also the honest value: Engineering and Product were both assessed relevant and both returned findings that changed the design (§Domain Review).

## Overview

Bundle 2 of 5 from the mattpocock/skills peer audit. Four mechanics from the peer's `diagnosing-bugs` and `setup-ts-deep-modules` skills are composed into existing Soleur surfaces, with no new skills: a red-capable feedback-loop completion gate and a ranked falsifiable-hypothesis ladder in `reproduce-bug` (after the observability pull, never instead of it); a removable `[DEBUG-<hex4>]` probe convention with a grep cleanup gate, kept distinct from the permanent `SOLEUR_*` marker class; a routing edge that turns "no correct regression seam exists" into a finding handed to `soleur:engineering:review:legacy-code-expert`; and an install-time bite-proof plus a README and an agent-instructions pointer emitted by `constraint-scaffold.sh`, keeping every existing hardening sentinel and the single-boundary scope.

**Narrative (from the issue): "Prove it, don't assert it."** Soleur's test and rule surfaces already refuse unmeasured claims; its debugging and scaffolding surfaces do not. `reproduce-bug`'s completion criterion today is the sentence *"Keep investigating until a good understanding of the situation is reached."* — unfalsifiable. `constraint-scaffold` proves its gate bites only inside its own hermetic `test/boundary.test.sh`, never in the founder's repo. This plan closes both.

**Peer source, pinned.** Both peer files were read at commit `c55ee46073ed923f86ce59a5eb3b6d895095d1b7` (committer date 2026-09-18T10:12:29Z — the same HEAD `plugins/soleur/NOTICE` already records for the bundle-1 audit): `skills/engineering/diagnosing-bugs/SKILL.md` (blob `061c25a5…`, 8529 B, 138 L) and `skills/in-progress/setup-ts-deep-modules/SKILL.md` (blob `7e30047e…`, 7546 B, 102 L). The LICENSE at that commit is MIT, `Copyright (c) 2026 Matt Pocock`. Every file **in Soleur's distribution** that takes prose from either carries, verbatim:

`<!-- Inspired by mattpocock/skills/<path> (MIT, Copyright (c) 2026 Matt Pocock). -->`

with `<path>` = `skills/engineering/diagnosing-bugs/SKILL.md` or `skills/in-progress/setup-ts-deep-modules/SKILL.md`. The one artifact the scaffold *emits into a founder's repo* (the README) is Soleur-authored user output and carries no peer sentence; the constraint is inapplicable to it by content, which AC2 checks mechanically (D8).

## Enhancement Summary

**Deepened on:** 2026-09-19
**Sections enhanced:** D3, D4, D5, D6, D8, Observability, Guard 1, Guard 3, Guard 4, Files to Edit, Phase 1/2/5, Test Scenarios, Acceptance Criteria; two new sections (`## Deepen-Plan Reconciliation (R45–R72)`, `## Precedent Diff`).
**Research agents used:** stub-prototype (general-purpose, ran today's script + emitted runner against a fixture-owned stub `depcruise`), verify-the-negative (15 claims, 15 confirmed), precedent-diff (8 patterns), git-history-analyzer (12 attribution claims, 12 confirmed), test-design-reviewer (Farley score 6.3/10 → recommendations folded), security-sentinel (0 P0, 5 P1, 7 P2), observability-coverage-reviewer (layer-7 audit), prompt-engineer (paste-ready prose, saved to `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/prose-drafts.md`).

### Key Improvements

1. **The stub `depcruise` is now specified from measurement, not assumption.** The emitted runner calls depcruise twice on the green path (`--output-type err`, then `--output-type json` parsed by `node`) and baseline capture calls it once (`--output-type baseline`, must be a JSON array). A stub that prints a checkmark for every call fails 71 at the pre-probe pass and poisons the baseline; the earlier `make_stub_depcruise <dir> <stdout> <rc>` could never reach a 72. The stub now branches on `--output-type` and on the probe directory's presence in its cwd (R45); the smallest working stub is pasted in D6.
2. **Three real false negatives closed in the cleanup gate and Guard 4** (R47–R49): `git grep` without `--untracked` misses a probe in a not-yet-added file — the exact file `test-fix-loop`'s next checkpoint would commit; `-I` silently skips files git classifies as binary; and Guard 4's `SOLEUR_[A-Z_]*DEBUG` predicate is **red on today's tree** (`SOLEUR_DEBUG_PERMISSION_LAYER` is a legitimate env flag in `apps/web-platform/server/permission-log.ts`) — narrowed to the emit call-form with `permission-log.ts` pinned as a must-PASS row.
3. **The meta-guard ledger would have reddened CI** (R50): `plugins/soleur/skills/*/test/` is in `guard-vacuity-floor.test.sh`'s `DEFERRED_DIRS` with a shrink-only `MAX_DEFERRED=47`; adding floors to `bite-proof.test.sh` and `parity.test.sh` requires promoting both into `PROMOTED_FILES` — a file the plan did not list. Added to Files to Edit.
4. **Residue and write-boundary holes closed** (R51–R55): the default-mode INT/TERM handler now removes the emitted executables (a TERM mid-bite otherwise left five artifacts and the next run at 66); `append_once` refuses a symlinked `CLAUDE.md`/`AGENTS.md`/`README.md` (a `CLAUDE.md -> ~/.claude/CLAUDE.md` link would have written into the founder's *global* instructions); `TMPDIR` inside the repo is refused; the two `mkdir -p` directories are `rmdir`'d on cleanup.
5. **Redaction became mechanical** (R56–R58): the single Phase 8 comment body and the `--cmd` string pass through the existing `plugins/soleur/skills/incident/scripts/redact-engine.py` (exit 1 = redaction needed) before posting; fixtures derived from a Sentry/Better Stack trace are synthesized or redacted before commit; probe payloads are discriminators only (never env values, headers, bodies, PII).
6. **Precedent adopted over invention** (R59–R66): signal handler `'cleanup; trap - EXIT; exit 143'` (`scripts/rotate-sentry-actions-ro-token.sh`); label creation per `scheduled-terraform-drift.yml` (no `--force`, which rewrites a founder's existing label); the 8-word shingle normalisation of `plugins/soleur/test/agent-originality.test.ts`; `schedule/SKILL.md`'s `--flag value` phrasing; `boundary.test.sh`'s trailer block verbatim (with `($cases rows)` suffix); stub argv logging + `exit 64` on unexpected argv.

### New Considerations Discovered

- `plugins/soleur/` is vendored into the production image, so `constraint-scaffold.sh` can also run on the hosted agent runner, where a 71–74 emits no `SOLEUR_*` marker and reaches no telemetry layer. Kept **out of scope by decision** (the operator's marker-population caution and AC13 stand); a mirrored-not-paged `SOLEUR_CONSTRAINT_SCAFFOLD_HALT` is Deferral 3 (R67).
- A real toolchain case for 72 was missing: a copied config with one rule at `severity: "warn"` yields `warn <rule>: …`, rc 0 → 72, and proves the `^\s*error ` anchor rejects `warn` lines (R68).
- Guard 1 has **14** rows (1–12 plus 3b/3c), not fifteen; floor constants are derived at commit time from `grep -c 'cases=\$((cases + 1))'` per segment (R69).

## READ THIS FIRST — the revisions block supersedes the body

An eight-seat review panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO, CPO, CMO) plus an advisor consult produced `## Plan Review Revisions (R1–R44)` at the end of this file. The body below has been rewritten to agree with them; where a sentence in the body and a revision disagree, the revision wins. The three structural reversals are: (1) the README and pointer are the **last** writes of a default-mode run, after the bite-proof, so the clean-tree guard inside baseline capture never sees them (R1); (2) the script carries **zero** test seams — every failure arm of the bite-proof is driven by a fixture-owned stub `depcruise` reached through the `node_modules` symlink (R11); (3) a failed bite in default mode **removes what it emitted**, so a founder repo is never left half-installed and un-re-runnable (R2).

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Check run | Verdict |
|---|---|---|
| #8288 is open and unresolved | `gh issue view 8288 --json state,title` → `OPEN`, labels `priority/p1-high type/feature domain/engineering`, milestone `Post-MVP / Later` | **Holds** |
| Bundle 1 (#8287) shipped as `129fcd4d5`; its compound as `e84d1dd32` | `gh issue view 8287` → `CLOSED`; `git log --oneline -1 129fcd4d5` → `feat(ship): operator-bootstrap skill … (#8297)`; `e84d1dd32` → `docs(learnings): the ship phase of #8297 …` — and `e84d1dd32` is this branch's merge-base with `origin/main` | **Holds** (context only, not work targets) |
| The audit "landed via PR #8284" (Tier 1 entry in `competitive-intelligence.md`) | `gh pr view 8284 --json state,mergedAt` → **`OPEN`, `mergedAt: null`**; `git grep mattpocock origin/main -- knowledge-base/product/competitive-intelligence.md` → zero hits | **STALE as phrased.** The audit PR is open, not merged. Nothing here depends on it; the issue body carries the line-by-line verdict this plan needs, and `plugins/soleur/NOTICE` already carries the peer entry (from #8297). No re-scope. |
| Sibling bundles #8289 / #8290 / #8292 are separate | all three `OPEN`; scopes are glossary + rejected-request register (#8289), invocation-axis budget + negation rewrite (#8290), roadmap Not-Yet-Specified (#8292) | **Holds.** This plan touches none of their files and must not close them. |
| `reproduce-bug` + `test-fix-loop` carry 0 of 6 `diagnosing-bugs` mechanics | functional-discovery grep of `plugins/soleur/{skills,agents}` for `hypothes\|falsif\|feedback loop\|red-capable\|minimi[sz]\|bisect\|DEBUG-\|seam` — the only hits are plan-time (`deepen-plan` SSH hypotheses), post-incident (`incident/templates/pir.md:63-69`), or GDPR data-minimisation | **Holds** |
| `grep -rn '\[DEBUG-' plugins/soleur/` returns zero | run 2026-09-19 → `0`; `git grep -n '\[DEBUG-' -- . ':!plugins'` → zero | **Holds** — and the *prefix* grep will stop holding the moment this plan lands, because the convention's documentation contains the prefix. The gates therefore key on the **shape of a real tag** (`\[DEBUG-[0-9a-f]{4}\]`, either case) and the documentation writes only the placeholder `<hex4>` (D4). |
| `SOLEUR_*` markers are deliberately permanent and mirrored | `apps/web-platform/server/git-lock-marker-telemetry.ts` › `MARKER_RE` (the `const MARKER_RE =` line) is a hand-maintained allowlist; `apps/web-platform/test/git-lock-marker-telemetry.test.ts` › `describe("drift guard: …")` collects **every** `echo "SOLEUR_…` / `printf 'SOLEUR_…` literal from `plugins/soleur/skills/*/scripts/*.sh` **wholesale**, plus `SKILL.md` prose filtered by `DOMAIN_RE = /^(SOLEUR_GIT_\|SOLEUR_WORKTREE_\|SOLEUR_SESSION_STATE_\|SOLEUR_[A-Z_]+_HALT$)/`, and requires each to be mirrored. Its `SENTINEL_RE` sees only the `echo "`/`printf '` call-forms, so a markdown table that *names* `SOLEUR_*` is invisible to it, and so is a `console.log("SOLEUR_DEBUG_x")` in `apps/web-platform/**` (architecture-strategist) | **Holds — with two binding consequences:** `constraint-scaffold.sh` must not gain any `SOLEUR_*` literal (it has none today; `log()` prefixes `constraint-scaffold:`), and Guard 4 carries a second predicate for a `SOLEUR_*DEBUG*` spelling anywhere in the tree, because the drift guard's population does not reach the realistic injection site (R22). |
| Soleur's hardening list (symlink refusal, empty-from-set, `(?!)`, merge-base baseline, `reachable: true` twin, zero-reachability-baseline guard, alias self-check, three generated workflows) | read `references/depcruise-config.template` (symlink hard error, `fromSet = ["(?!)"]`, the empty-from-set throw), `shared-runner.template` (`REACHABILITY_ENTRIES`, `UNRESOLVED`), `constraint-scaffold.sh` › `capture_baseline_mergebase()`, and the three `sed "s\|__TARGET_DIR__\|…"` emits | **Holds** — all eight are present and none is touched by this plan. |
| Both rules fire on a direct probe (needed to assert "fail **naming the rule**") | **Measured** with the dogfood runner (`CONSTRAINT_GATES_DIR=<fixture> bash apps/web-platform/scripts/constraint-gates.sh`, depcruise 16.10.4): a direct `"use client"` value import of `@/server/__constraint_scaffold_bite_probe__` prints `error no-client-to-server-secret-transitive: …` **and** `error no-client-to-server-secret: …`, rc=1; Kieran re-measured the **one-hop** shape: `error no-client-to-server-secret-transitive: …/via-hop.tsx` and `error no-client-to-server-secret: …/direct.tsx` on their own edges, rc=1; clean tree before and after: `✔ no dependency violations found`, rc=0 | **Holds today — and is deliberately NOT relied on for the transitive rule.** D6 injects a one-hop chain and asserts each rule on the edge it exists for (advisor). |
| A refreshed baseline can grandfather the probe | dependency-cruiser softens known violations per **origin** (`from` + rule name — `shared-runner.template` comment block and the 2026-07-01 learning). The probe's `from` is a path that has never existed, so no baseline entry can match it | **Does NOT hold** as an argument for refresh-mode bite. What refresh-mode bite catches is config/runner drift between runs on the real target (D7, corrected per CTO). |
| The emitted runner tolerates a target without `components/` | `shared-runner.template` cruises `app components server` hard-coded; **measured** (Kieran, spec-flow, depcruise 16.10.4): a missing dir → `Can't open 'components' for reading`, rc=1 — `boundary.test.sh` creates an empty `app/` for exactly this reason | **Does NOT hold.** An `app/`-only target can never pass its own CI today; the bite-proof's "else `app/`" arm was unreachable. Replaced by a precondition that all three dirs exist (R4). |
| `reproduce-bug`, `test-fix-loop`, `constraint-scaffold` are in the ADR-229 byte ratchet | `plugins/soleur/test/skill-body-budget.json` rows: brainstorm, deepen-plan, one-shot, qa, compound, plan, postmerge, review, ship, work | **None of the three is in the lifecycle set.** `ship` **is** (ceiling 274 000 B; measured 266 104 B → 7 896 B headroom), and this plan adds one line to it (R24), so `scripts/lint-skill-body-budget.py --base <merge-base>` is load-bearing for that one edit. |
| Phase renumbering in `reproduce-bug` breaks a live reference | repo-research + architecture-strategist grep across `plugins/**`, `.claude/hooks/`, `scripts/`, `.github/workflows/`, `apps/`, `knowledge-base/` (non-archive): every surface references the skill by **name** (`phase-surface-map.{json,ts}`, `ship`, `work-lifecycle-parallel.md`, `devin-cloud-mode.test.ts`, eval-harness enums, `agents.manifest.json`); the only phase-number citations are historical plans. Two **content** pins exist: `apps/web-platform/test/plugin-root-anchoring.test.ts` pins `reproduce-bug/SKILL.md -> redact-a11y-snapshot.py`, and `plugins/soleur/test/devin-cloud-mode.test.ts` › "every marked SKILL.md carries exactly one byte-identical block" pins the `soleur-cloud-mode` block | **Holds** — renumber freely; keep the `redact-a11y-snapshot.py` reference verbatim and put the attribution comment strictly **between** the frontmatter close and the cloud-mode block, never inside it (R27). |
| `parity.test.sh` has five rows | **Measured** (Kieran): it prints `8 passed` today — rows 1–5, 6a, 6b, 6c | **STALE in the earlier draft.** New rows are **7–8**, floor **10** (R6). |
| `grep -c hr-no-dashboard-eyeball-pull-data-yourself` on `reproduce-bug/SKILL.md` is 2 | **Measured** (Kieran): 1 | **STALE.** AC3 asserts `≥ 1` (R7). |
| No open code-review scope-out touches the planned files | `gh issue list --label code-review --state open --json number,title,body --limit 200` (65 issues) piped through standalone `jq --arg path` for each planned path | **Holds** — zero matches (§Open Code-Review Overlap). |
| `bin/dev` (named in the Playwright block) exists | `ls bin/dev apps/web-platform/bin/dev` → neither; the dev script is `apps/web-platform/package.json` › `scripts.dev` | **STALE.** The line is also an operator-ask a non-technical founder cannot satisfy (CPO). Rewritten in D1 as the one other changed line in the Playwright block. |
| `action-required` exists where the seam verdict labels the issue | `gh label list` → exists **in Soleur's repo**; `operator-digest/SKILL.md` §"4. Action needed from you" reads `gh issue list -R jikig-ai/soleur --label action-required` — **hard-wired to Soleur** | **Partially holds.** The label may not exist in a founder repo (`gh issue edit --add-label` then fails), and the digest reaches only Soleur's own issues today. D5 creates the label idempotently and scopes the founder-facing claim (R28). |

### Property List (Phase 0.6b)

| # | Property (observable outcome) |
|---|---|
| P1 | A bug investigation cannot reach a hypothesis until one **named command**, already run once, goes red on the user's exact symptom — and after the fix the founder's agent re-runs that command on request and shows it green. |
| P2 | Hypotheses are written as symptom predictions before any is tested, ranked, and put to the founder as a decision with a default (proceed / re-rank / add a fact), and the winning one is recorded where the next debugger reads it. |
| P3 | No temporary probe ships with a fix: every probe added during a diagnosis is removable by one grep keyed to its shape, and can never be confused with — or mirrored as — a permanent monitored `SOLEUR_*` marker. |
| P4 | When no correct seam exists for a regression test, the investigation reports *that* as the finding, hands it to the agent that already knows Feathers' seam techniques, and labels the issue `action-required` — which the weekly digest carries to the founder when the digest runs against that repo (today: Soleur's own). |
| P5 | Every `constraint-scaffold` run that reports success leaves the founder's repo with a gate that has been **observed** to reject a real violation (naming both rules, each on its own edge) and to accept the tree without it — never merely emitted — and a run that cannot prove it leaves the repo exactly as it found it. |
| P6 | An agent working in the founder's repo discovers the import-boundary rule from the repo's own instructions before tripping over it in CI. |

### Cut List (Phase 0.6b)

| Mechanism the ask proposed or research suggested | Property | What already covers it / why cut | Disposition |
|---|---|---|---|
| A **prefix** grep (`\[DEBUG-`) as the cleanup gate | P3 | Self-referential: the convention's own documentation contains the prefix. Replaced by a **shape** grep for a real tag with a placeholder discipline in the docs (D4). | **CUT the prefix form.** |
| Peer's `scripts/hitl-loop.template.sh` (HITL rung 10) | P1 | Soleur already has human-in-the-loop mechanisms with provenance (`soleur:agent-browser`, the Playwright path). Importing it would also be a file taking peer *code*, not prose. | **CUT.** Rung 10 stays as prose pointing at `soleur:agent-browser`. |
| A bite-proof step inside the generated CI workflow (continuous bite) | P5 | The runner's own fail-closed self-checks (`couldNotResolve==0`, zero-reachability guard) and `test/boundary.test.sh` in Soleur's CI buy continuous non-vacuity; writing probe files in an untrusted `pull_request` context is the write ADR-074 removed. | **CUT** (Deferral 2 records it as the stronger long-term home the CTO named). |
| Bite **in place** in the founder's working tree | P5 | The clean-tree guard already makes HEAD ≡ working tree, and `capture_baseline_mergebase()` already owns a throwaway-worktree pattern in the same script. A detached-HEAD worktree proves the identical gate on identical content with **zero residue class**. | **CUT in-place; ADOPT worktree** (D6, per CTO + CPO). |
| Environment-variable test seams in the production script (`CONSTRAINT_SCAFFOLD_TEST_*` + a master switch) | P5 (testability) | The fixture already owns the target's `node_modules` symlink; a fixture-owned stub `depcruise` binary drives every failure arm (rc, output shape, a TERM mid-run) without a single production seam. | **CUT all seams** (R11 — DHH, code-simplicity, CTO converged). |
| `references/readme-emit.sed` as a shared transform file | P6 (parity) | Every existing parity row inlines its `sed` on both sides and lets the template be the anchor; a Guard 2 row that reds on divergence is the mechanism, not a shared file. | **CUT** (R9 — both panels). |
| The untracked-file `note:` line + its case | P5 | Never fails, nothing reads it, and it would have counted the scaffold's own just-emitted README on every first install. The README states the proof covers committed files. | **CUT** (R19 — both panels). |
| The `app/`-only placement arm | P5 | Unreachable: the emitted runner hard-codes `components`. | **CUT**; replaced by a precondition (R4). |
| Borrowing obra/superpowers', addyosmani's, melodic-software's additions | P2/P4 | Each is a *third* upstream needing its own NOTICE entry and attribution comment; the routing stop is expressible from `test-fix-loop`'s **own** termination table in Soleur's words. | **CUT the imports; keep the routing in native prose** (D5). |
| Editing `legacy-code-expert.md` | P4 | The agent already classifies seams and plans characterization tests (`legacy-code-expert.md` › "Step 3: Identify Seams"); spec-flow verified it accepts the hand-off with no edit. | **CUT** per the issue. |
| A new digest input for the seam-absence finding | P4 | `operator-digest/SKILL.md` §4 already reads open issues labelled `action-required`, and its path scope forbids new sources. Labelling the issue is the whole mechanism. | **CUT the new source; ADOPT the label** (D5, per CPO). |
| A five-arm pointer-file precedence + a deferral for level six | P6 | v1 has one hard-coded target one directory below root; `apps/web-platform/{CLAUDE,AGENTS}.md` do not exist. | **CUT to two arms at the repo root** (R32). |
| The two-class marker table repeated in three places | P3 | One normative copy (ADR-230); the skill needs the spelling, the mint, the decision rule and the cleanup command. | **CUT the copies** (R25). |

Nothing in the Cut List removes a property; every cut replaces a mechanism with one already on `origin/main` or with a narrower form of the same mechanism.

### Value-Proposition Measurement (Phase 0.6c)

No cost or performance saving is claimed. The one measurable *cost* is added: `--refresh-baseline` and the default mode each gain three runner invocations (two of which also run the runner's JSON alias self-check) plus one `git worktree add/remove` pair. Phase 0 records the wall-clock of one runner pass on `apps/web-platform` so the review panel sees the number rather than an adjective (Task 0.4).

### Measured budgets (Phase 1.8)

- **Skill description budget:** `SKILL_DESCRIPTION_WORD_BUDGET = 2499` at `plugins/soleur/test/components.test.ts:21`. **This plan edits no `description:` frontmatter**, so the budget is untouched and `cq-skill-description-budget-headroom` does not fire.
- **ADR-229 byte ratchet:** applies to the one-line `ship/SKILL.md` edit only (7 896 B headroom measured). The three main skills are outside the lifecycle set.
- **AGENTS always-loaded budget:** untouched — no AGENTS rule, no AGENTS pointer. The dogfood pointer line goes to `CLAUDE.md` (currently the single line `@AGENTS.md`) as **plain prose with a repo-relative path — never the `@path` import form** (CTO); `lint-agents-rule-budget.py` does not measure `CLAUDE.md`; per-session cost is one ~170-byte line, and the ADR-071 amendment records this as the first product-specific line in that file (CPO).
- **P1b relative-operand baseline** (`plugins/soleur/test/fixture-relative-assert.baseline.txt`): `constraint-scaffold.sh` carries **10** rows today; `boundary.test.sh` 11, `generator.test.sh` 3, `emit-fix-constraints.test.sh` 1. Row-by-row equality is enforced; whether the new operands move the count depends on the scanner's rooting rules (CTO), so Task 5.4 is written as *if it reds, regenerate* — and the regeneration is diffed against the old file so only the expected rows moved (R15).
- **Tempfile-ownership highwater:** 79 today, but the number moves under in-flight PRs (78→79→80→78→79 in its own history), so AC15 asserts `--check-highwater` exit 0, never `== 79` (R15). The one new `mktemp -d` sits inside the shared worktree helper under an owning `EXIT INT TERM` trap.
- **Next free ADR ordinal:** `ADR-230` — enumerated across every `origin/*` ref on 2026-09-19 (highest is `ADR-229`). Provisional; re-derived before merge.
- **Guard 4 population:** `git ls-files -- . ':!knowledge-base' | wc -l` → **5 168** tracked non-KB files (spec-flow). The floor is set at **2 500** — under half of today's population, so a repo split cannot false-fail it while a scanner that stopped looking still can (R41).

### Other measured repo facts

- `apps/web-platform/node_modules/.bin/depcruise` is installed locally (16.10.4); `apps/web-platform/server/README.md` **does not exist**; `apps/web-platform/{CLAUDE,AGENTS}.md` do not exist; repo-root `CLAUDE.md` is exactly `@AGENTS.md`; `apps/web-platform/tsconfig.json` excludes only `node_modules`; the config's `walk()` skips only `node_modules` and `.next`, so a `__constraint_scaffold_bite_probe__` directory is scanned.
- `scripts/test-all.sh` › `SUITE_GLOBS` includes `plugins/soleur/skills/*/test/*.test.sh` and `plugins/soleur/test/*.test.sh`, so both new suites auto-register; `scripts/lint-orphan-test-suites.sh` is the decision point and must report `0 orphaned`.
- `test/boundary.test.sh` reads the **dogfood** config and runner, not the templates; `test/parity.test.sh` (8 rows today) pins templates ↔ dogfood byte-parity. Any new emitted artifact needs a parity row or it is untested on the dogfood side.
- `test/generator.test.sh` exercises only paths that bail **before** baseline capture and carries no ADR-193 floor (Deferral 1).
- `constraint-scaffold.sh` › `log()`/`die()` write to **stderr**; the plan's failure messages therefore also go to stdout via a `verdict_fail()` helper (R13), because agent runtimes surface stdout and swallow stderr (`provision-doppler.sh:12-13`).
- The runner's violation annotation (`shared-runner.template`, the `::error::constraint-gates: client->server-secret import-boundary violation(s)` line) goes to **stderr** and contains neither rule name; only its zero-reachability message carries the bare token `no-client-to-server-secret-transitive`. depcruise's own `error <rule>: <from> → <to>` lines go to **stdout**. `prove_bite()` captures `2>&1` into a file and anchors on the call-form, so stderr prose cannot satisfy the assertion (R5).
- ADR-226 enforcement is `plugins/soleur/test/harness-parity-tree.test.ts` (`expect(noncanonical).toEqual([])` over every skill doc). Every agent/skill reference this plan adds is spelled `soleur:engineering:review:legacy-code-expert`, `soleur:test-fix-loop`, `soleur:reproduce-bug`, `soleur:agent-browser`, `soleur:constraint-scaffold`, `soleur:operator-digest`.
- `scripts/lint-infra-no-human-steps.py` scans `knowledge-base/` only, so it gates **this plan file**, not the skill prose. `scripts/markdown-lint.sh` sweeps every tracked `*.md`, so the dogfood `apps/web-platform/server/README.md` must lint clean (the `.template` source is not swept). `.github/scripts/test/test-no-at-mention-credfile-footgun.sh` scans root `CLAUDE.md` for `@/home|/tmp|~` — a plain repo-relative path is safe.
- `test-fix-loop/SKILL.md` Phase 0 parses `$ARGUMENTS`: "contains a number → max iterations" — a red-capable command such as `npx vitest run test/issue-8288.test.ts` contains digits and would be swallowed (spec-flow). The hand-off therefore uses an explicit `--cmd '<command>'` / `--max N` form (R18).
- `test-fix-loop` Phase 0 "Require Clean Working Tree" STOPs and tells the user to commit; the reproduce-bug hand-off must therefore happen **after** Phase 9 cleanup with the loop script committed by the agent (R17).
- Attribution precedent (bundle 1): SKILL.md carries the comment on the first line after frontmatter (`operator-bootstrap/SKILL.md:6`); shell scripts carry it as `# <!-- Inspired by … -->` (`operator-script.sh:128`). `plugins/soleur/NOTICE` › `mattpocock/skills` entry lists `Used in:` / `Portions adopted:` and already pins the SHA; there is no test pinning NOTICE ↔ comment consistency, so AC17 does it by grep.
- `ship/SKILL.md:2656` is the precedent for `gh label create <name> … 2>/dev/null || true` before an `--add-label` (architecture-strategist).

### Institutional learnings that change a decision

- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` — a hypothesis table may not read CONFIRMED/REFUTED while its discriminator is unobservable. Folded into Phase 5's format: each hypothesis names its **discriminating observation** and where it will be read, and the verdict column is UNKNOWN until that observation exists.
- `knowledge-base/project/learnings/2026-07-15-a-reproduced-symptom-does-not-validate-the-mechanism-you-attached-to-it.md` — already cited in `reproduce-bug`'s "Execute the mechanism" bullet; Phase 4 (minimise) is placed **before** hypotheses so the A/B-one-variable rule has a minimal fixture.
- `knowledge-base/project/learnings/workflow-patterns/2026-07-02-merged-is-not-deployed-on-concierge-instrument-dont-ask.md` and `…/2026-07-08-self-pull-observability-in-diagnostic-loops-never-ask-operator-to-fetch.md` — the existing blind-surface bullets are the **permanent-marker** arm; Phase 6 states the decision rule so the two never blur, and Phase 2's "cannot build a loop" arm hands off to exactly that bullet (D1).
- `knowledge-base/engineering/architecture/decisions/ADR-193-anti-vacuity-floor-contract.md` — floors report with `printf >&2; exit 1` directly; case counter at the call site; conservation first. `scripts/guard-vacuity-floor.test.sh` derives its population **by shape**: a conditional whose test compares a counter the file increments (`X=$((X + 1))`) against a threshold (`[[ "$cases" -lt "$MIN" ]]`) — the new floors use exactly that form so the meta-guard sees them (R41).
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — harness rows and must-PASS non-canonical fixtures are mandatory in every Guard entry.
- `knowledge-base/project/learnings/2026-07-06-ac-self-reference-grep-trap-and-verify-config-enabled-state.md` — drives D4's shape-grep + placeholder discipline.
- `knowledge-base/project/learnings/2026-07-28-my-ac-verified-four-paths-while-ci-verified-five.md` — every "gate is green" AC runs the gate's own invocation with its own input derivation.
- `knowledge-base/project/learnings/security-issues/2026-07-01-depcruise-reachability-baseline-softens-per-rule-name-ignoring-type.md` — the per-origin softening is why a fresh-origin probe can never be grandfathered (Premise table), which corrected D7's rationale.
- `knowledge-base/engineering/architecture/decisions/ADR-129-jq-argv-ceiling-and-shell-cleanup-ownership.md` — bash traps replace, never stack. The shared worktree helper (R33) owns exactly one trap at a time and clears it before returning; `lint-trap-tempfile-ownership.py` rule (c) is file-scoped (any `trap … EXIT` in the file satisfies it) — the ordering requirement is ADR-129's, not the lint's (Kieran).
- `knowledge-base/project/learnings/2026-09-13-cc0-legal-template-vendoring-eval.md` + constitution line 192 — vendored third-party credit stays in the corpus for provenance and is stripped from emitted user output (D8).

### Scoped advisor consult (Step 4.5, `advisor` tier)

Six points returned; disposition: (1) *bite tree ≠ baseline tree* — partially a misread (the clean-tree guard forbids tracked divergence; the baseline is captured at the merge-base); the untracked-file gap is real but its `note:` mechanism was later cut by both review panels — the README states the proof covers committed files; (2) *transitive rule asserted on a direct edge* — **adopted**: one-hop probe, each rule on its own edge, depcruise version in the verdict (D6); (3) *Guard 4 fixtures must be synthesized; grep case-insensitive* — **adopted** (D4, Guard 3/4); (4) *split the Phase 5 ratchets into a follow-up PR* — **declined as a misread**: Phase 5 runs existing gates, it adds none; (5) *Playwright rung ordering vs the Phase 2 stop* — **adopted** as one sentence at the gate (D1); (6) *master seam switch* — **superseded**: the panel removed every seam instead (R11).

### Open Code-Review Overlap

None. All planned paths were searched against the 65 open `code-review` issues; zero matches.

## Decisions

### D1 — `reproduce-bug` is renumbered 5 → 9 phases; observability stays Phase 1

Nothing live cites a `reproduce-bug` phase number (Premise table), so the peer's discipline is composed as whole phases. The mapping:

| New | Title | Source | Change |
|---|---|---|---|
| 1 | Log Investigation | existing Phase 1 | Body unchanged. Only the terminal sentence *"Keep investigating until a good understanding of the situation is reached."* is replaced by: *"Phase 1 ends when telemetry has named the operative error, or you have measured that it does not carry one (the helper's coverage verdict, not an empty result). Either way, Phase 2's gate is the completion criterion — telemetry tells you where to point the loop; it is not the loop."* `hr-no-dashboard-eyeball-pull-data-yourself` keeps first position by construction. |
| 2 | Build a feedback loop | peer Phase 1 | **New.** Ordered **decision first, menu second** (CTO): (a) the "Redact" paragraph (`<REDACTED>`, loops built against env vars, quote only signal lines), extended to the two places redaction was otherwise manual: **a fixture derived from a captured trace** (rung 5's Sentry payload / Better Stack rows) is synthesized or redacted before it is committed in Phase 9 (`cq-test-fixtures-synthesized-only`; Sentry exception values carry emails and tokens), and **the whole Phase 8 comment body plus the `--cmd` string** is written to a temp file and passed through `python3 "${CLAUDE_PLUGIN_ROOT}/skills/incident/scripts/redact-engine.py" <file>` — the repo's existing redactor, exit 1 = redaction needed — and posted only on exit 0 (security-sentinel P1); (b) the completion criterion — the four checkboxes red-capable / deterministic / fast / agent-runnable, where **agent-runnable means the agent starts what the loop needs itself**, a backgrounded dev server included, and never asks the founder to start a server or paste output — and the hard gate *"no red-capable command, no Phase 5"*; (c) **"When you genuinely cannot build a loop"** — a *stop*, each option a decision-with-default: first and default, *add instrumentation* (temporary `[DEBUG-<hex4>]` where a loop will follow; for a blind production surface, Phase 1's existing bullet — add a permanent `SOLEUR_*` marker so the next occurrence self-reports, write `no loop buildable yet; instrumentation added: SOLEUR_<…>; re-run soleur:reproduce-bug on the next occurrence` into the Phase 8 comment, and end the run); second, *environment access* — **non-shell only**: a preview or staging deploy to drive, a flag to flip, `soleur:trigger-cron` to fire; SSH and `docker exec` are never an ask, and a blind production surface takes the first arm (`hr-no-ssh-fallback-in-runbooks`; observability-coverage-reviewer); last and bounded, *a redacted captured artifact* (HAR, log dump, recording) — the one ask that is data retrieval, permitted only after the ladder and the instrumentation route are exhausted, because a founder's local device state is the one thing no instrumentation can capture; **the agent performs the redaction** (HAR: strip `cookies`, `Authorization`/`Cookie`/`Set-Cookie` headers and `postData` before reading), the artifact is never attached to the issue and never lands under `knowledge-base/`, and it is deleted when the run ends (security-sentinel). Headless: take the instrumentation arm and end with the comment. No silent downgrade to rung 10; **for a UI bug, Phase 3 is how rung 4 is built — go there and come back before declaring that no loop exists**; (d) the 10-rung ladder under `### Ways to construct one` (rung 4 → Phase 3; rung 5 gains one Soleur clause — *the Sentry event payload or Better Stack rows you pulled in Phase 1 are a captured trace*; rung 10 → `soleur:agent-browser`); (e) "Tighten the loop"; (f) the non-deterministic branch. Nothing is posted to the issue in this phase — every line destined for the founder is carried to the single Phase 8 comment (R14). |
| 3 | Visual Reproduction with Playwright | existing Phase 2 | Prose byte-identical (the #7947/#7980 credential-safety text and the ADR-179 preflight are security-load-bearing; `plugin-root-anchoring.test.ts` pins the `redact-a11y-snapshot.py` reference) **except two lines**: (a) one added non-blank line under the heading — *"This is rung 4 of the Phase 2 ladder. A screenshot is evidence; the loop is the script whose assertion goes red."*; (b) the stale operator-ask *"If server not running, inform user to start `bin/dev`."* becomes *"If the server is not running, start it yourself in the background (`cd apps/web-platform && npm run dev` here; the target repo's dev script elsewhere) and poll until it answers — never ask the founder to start it (`hr-exhaust-all-automated-options-before`)."* |
| 4 | Reproduce + minimise | peer Phase 2 | **New.** The three confirmations (user's failure mode, reproducible at rate, exact symptom captured) and the minimise pass — cut one element at a time, re-run after each cut, done when every remaining element is load-bearing. In scope per the issue (B3 "Also import minimisation"). |
| 5 | Hypothesise | peer Phase 3 | **New.** 3–5 ranked, each in the *"If X is the cause, then changing Y will …"* form, plus a **Discriminator** column (what observation decides it and where it is read); rendered to the founder as *"what else you'd see if this is it"* (CTO). Put to the founder as a **decision with a default**, in the same turn, **without a question tool** — the ranked table is presented and the agent continues; the founder's veto is an interrupt (CTO, CPO): *"Here are the 3–5 likeliest causes, ranked; each says what else you would see if it were true. I will test them in this order unless you tell me one is wrong or you saw something that changes the order — proceed / re-rank / add a fact."* Symptom language, never code paths. **Headless (one-shot, cloud, no TTY):** the Phase 8 comment carries `founder checkpoint not presented (headless); proceeded with the agent's ranking` so the decision is auditable. |
| 6 | Instrument | peer Phase 4 | **New.** Probe ↔ prediction mapping; one variable at a time; debugger > targeted log > never log-everything; the removable-probe convention in its **minimal in-skill form** — spelling, mint command, decision rule, cleanup command, and a citation of ADR-230 for the full two-class table (D3, R25); the perf branch (baseline measurement — timing harness, profiler, `EXPLAIN` — then bisect; measure first, fix second). In scope per the issue (B2 "Also import the perf branch"). |
| 7 | Document Findings | existing Phase 3 | Existing bullets kept. Adds the **Regression seam verdict** bullet (D5). |
| 8 | Report Back | existing Phase 4 | The **single** issue comment of the run. Adds items 6–8: the red-capable command with its redacted invocation + output (*"a command your agent re-runs on request — red before the fix, green after — and shows you the result"*); the ranked hypotheses with verdicts (UNKNOWN allowed; CONFIRMED only with the discriminating observation quoted) and the headless line when applicable; the seam verdict. Item 5 "Suggested Fix" names the next step: *"after Phase 9, commit the loop script yourself and hand it to `soleur:test-fix-loop --cmd '<the command>' --max 5` so the fix iterates on the user's symptom, not on a proxy"* — after cleanup, never before, because `test-fix-loop` requires a clean tree and would otherwise hand the founder a git instruction (R17, R18). |
| 9 | Cleanup | existing Phase 5 | Screenshot cleanup kept. Adds the checklist: original repro re-run and green; regression test passes **or** seam absence documented; **no temporary probe ships with the fix** — the shape grep (D4) prints nothing; throwaway harness deleted or moved to a named debug location; **no production payload in the committed loop script or fixture**; the confirmed hypothesis stated in the Phase 8 comment; the loop script committed. |

### D2 — Wiring is the pipeline the issue names: `reproduce-bug → test-fix-loop → legacy-code-expert`

Today no edge exists between `reproduce-bug` and `test-fix-loop`, and nothing references `legacy-code-expert` outside its own file. This plan creates the edges in prose, canonically spelled (ADR-226):

- `reproduce-bug` Phase 8 → `soleur:test-fix-loop --cmd '<command>' --max N` (after Phase 9).
- `reproduce-bug` Phase 7 → `soleur:engineering:review:legacy-code-expert` (Task) when no correct seam exists. The Task prompt hands it what its "Step 1: Identify the Change Point" expects: the minimised repro command and file set from Phase 4, the call-site chain, and the candidate seams already rejected as too shallow; it is asked for its standard `Change Analysis` / `Recommended Approach` output (spec-flow verified: no agent edit needed).
- `test-fix-loop` Diagnostic Report → `soleur:engineering:review:legacy-code-expert` on CIRCULAR / NON_CONVERGENCE, or when a fix landed with no test asserting the changed behaviour.

`test-fix-loop` Phase 0 gains the explicit argument form: *"`--cmd '<command>'` sets the test command and `--max N` the iteration cap; when either is present it wins over the number/command heuristics below (a red-capable command from `soleur:reproduce-bug` usually contains digits)."* Its "NOT for writing new tests" boundary is preserved: it routes, it does not write the characterization test. `workflow-fidelity.ts` › `HANDOFF_SKILLS` is untouched — none of the three skills is an FSM node (Task 0.3 proves it).

### D3 — `[DEBUG-<hex4>]` is a removable class; `SOLEUR_*` is the permanent class; ADR-230 holds the table, the skills hold the rule

The normative two-class table lives in **ADR-230 only** (R25). `reproduce-bug` Phase 6 carries the four lines an agent needs mid-diagnosis:

- **Spelling:** `[DEBUG-<hex4>]` — exactly four hex characters, minted once per investigation with `printf '[DEBUG-%04x]\n' $((RANDOM % 65536))` (pure bash; no `openssl` dependency on a founder-repo path — CTO).
- **Decision rule:** the signal dies with the fix → `[DEBUG-<hex4>]`; the signal must outlive the fix (a blind surface, a recurring class) → a permanent `SOLEUR_*` marker via Phase 1's blind-surface bullet. **Never** spell a probe with a `SOLEUR_` prefix: the permanent class is defined by `MARKER_RE` (`apps/web-platform/server/git-lock-marker-telemetry.ts`) and its drift guard, and a `SOLEUR_*DEBUG*` spelling is caught by Soleur's CI (Guard 4).
- **Payload:** the discriminator only — booleans, lengths, ids, hashes. Never an env value, a header, a request body, PII, or a raw user-controlled string (a probe removed before merge has already reached Better Stack/Sentry retention if a preview deploy ran in between — CWE-532; interpolating user input into a log line is CWE-117). Probes are removed before any **push**, not only before commit.
- **Cleanup:** the D4 command.
- **Documentation:** always the placeholder `<hex4>`, never a concrete tag; cite ADR-230.

`test-fix-loop` cites the same ADR in one sentence. The issue's example tag `a4f2` is **not** used anywhere.

### D4 — The cleanup gate greps for the shape of a real tag, tree-wide, either case

```bash
git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'   # expected: no output
```

Case-insensitive because a hand-typed `[DEBUG-ABCD]` is the realistic leak (advisor). `--untracked` because a probe usually lives in a file that has not been `git add`ed yet — the exact file the next `test-fix-loop` checkpoint would commit (security-sentinel, measured: without the flag the grep is silent on an untracked `.ts`). **No `-I`**: git's binary heuristic skips a UTF-8 `.ts` containing one NUL byte and anything under a `-diff` gitattribute (measured); a "Binary file … matches" line is still non-empty output, which is the property. The exclusion is `knowledge-base/**/*.md`, not the whole directory — nine executable files are tracked under `knowledge-base/` today. Tree-wide is stronger than diff-scoped: a probe committed in an earlier `test-fix-loop` checkpoint is still in the tree. `knowledge-base/` is excluded only because a learning may quote a real tag from a session. The command runs at **three** sites so the chokepoint is real (architecture-strategist, R24): `reproduce-bug` Phase 9; `test-fix-loop` **before every checkpoint commit** (§4, ahead of `git add -A && git commit … checkpoint`) **and** before the success-row `git add -A` — on output, remove the probes and re-run the suite (a probe removal is not a "fix" and never stages as one); and one bullet in `ship`'s pre-PR checklist, the last skill to touch a tree before a PR. Soleur's own CI runs the same predicate over tracked files (Guard 4).

### D5 — Seam absence is a finding with a named receiver and a label; `test-fix-loop` routes on its own termination table

`reproduce-bug` Phase 7 gains a required bullet: *"**Regression seam verdict.** Name the seam where the fix's regression test will exercise the real bug pattern as it occurs at the call site (file + entry point). If the only seam available is too shallow — a single-caller test when the bug needs the chain, a unit that cannot replicate the trigger — **write `no correct seam` as the finding**: the architecture is preventing the bug from being locked down. Spawn `soleur:engineering:review:legacy-code-expert` (Task) with the minimised repro and the call-site chain; carry its seam analysis and characterization-test plan into the report. Then `gh label create "action-required" --description "Needs a human action" --color "B60205" 2>/dev/null || true; gh issue edit <N> --add-label action-required` (the exact form of `.github/workflows/scheduled-terraform-drift.yml`, the one shipped `action-required` creator; **never `--force`**, which rewrites a founder's existing label's colour and description on every run) — `soleur:operator-digest` reads that label when it runs against this repo (today: Soleur's own), and the digest is where a non-technical founder reads it as **'we cannot yet add an automatic test that keeps this bug from coming back'**; elsewhere it is a labelled issue the agent surfaces at the next session."* The peer's sentence *"If no correct seam exists, that itself is the finding"* is imported in those words (agent-facing). The founder-facing claim is per-investigation; recurrence across issues is the digest's observation (CPO).

`test-fix-loop` gains, in the Diagnostic Report's **Recommendation**: *"CIRCULAR or NON_CONVERGENCE on one cluster is an architecture signal, not a fix signal: recommend `soleur:engineering:review:legacy-code-expert` for that cluster's seams and characterization tests before another loop. Likewise when a fix landed but no existing test asserts the behaviour it changed — this loop never writes tests, so name the agent that should."* No third-party phrasing there.

### D6 — The bite-proof runs in a detached HEAD worktree through a shared helper, names both rules on their own edges, cleans up after itself, and carries no test seams

**Shared helper (R33, refined R59/R52/R53).** `with_detached_worktree <ref> <fn>`: `WT="$(mktemp -d)"` (same-line shape, so `lint-trap-tempfile-ownership.py`'s `mktemp` regex sees it); refuse a `TMPDIR` inside the repo — `case "$(realpath "$WT")" in "$REPO_ROOT"/*) die "TMPDIR resolves inside the repository; refusing to create the bite worktree there" 69;; esac` — so the worktree and its logs can never land in the founder's tree as untracked files (security-sentinel); installs `trap '_wt_cleanup' EXIT` and `trap '_wt_cleanup; trap - EXIT; exit 143' INT TERM` **before** `git -C "$REPO_ROOT" worktree add --detach "$WT" "$ref"` (the signal arm clears `EXIT` inside itself so cleanup runs once — the precedent at `scripts/rotate-sentry-actions-ro-token.sh` › the `trap 'cleanup; trap - EXIT; exit 143' TERM HUP` line; the repo splits 130/INT vs 143/TERM in three of four precedents, this helper uses 143 for both because Guard 1 pins one code and the distinction buys nothing here); calls `<fn> "$WT"`; removes the worktree; `trap - EXIT INT TERM`. `_wt_cleanup` in **default mode** also removes the six emitted artifacts and `rmdir`s the two `mkdir -p` directories if empty, then prints one stdout line `constraint-scaffold: interrupted; removed: <list>` — a TERM mid-bite must not leave the repo at 66 (observability-coverage-reviewer). Every runner invocation is written `rc=0; bash … >"$WT/bite-N.log" 2>&1 || rc=$?` — under `set -e` a bare non-zero runner call would abort the scaffold before the arm dispatch (stub-prototype). `capture_baseline_mergebase()` becomes a caller (its own inline sequence and trap go away), and `prove_bite()` is the second caller — one trap owner, no ordering hazard between two copies (DHH, ADR-129). An INT/TERM handler that `exit 143`s is what makes "exits on TERM" a property rather than an accident (Kieran).

**Precondition (R4).** Before anything is emitted, the default mode requires `app/`, `components/` and `server/` to exist under the target (`die "target $TARGET_REL lacks one of app/ components/ server/ — the emitted runner cruises all three and would fail its own CI" 65`). The README names the requirement.

**`prove_bite()`**, called at the tail of **both** modes:

1. **Stage.** Inside `with_detached_worktree HEAD`: copy the three artifacts that may be uncommitted — `$CFG`, `$RUNNER` (`chmod +x`), `$BASELINE` — into `$WT/$TARGET_REL` (in refresh mode all three are committed and the copy is a no-op by content; the clean-tree guard ran first, so working tree ≡ HEAD for tracked files — the ordering dependency is stated in a comment), and `ln -s "$TARGET/node_modules"` exactly as the baseline capture does (the 68 message names hoisted `node_modules` as a cause — code-simplicity). Every runner invocation below is `CONSTRAINT_GATES_DIR="$WT/$TARGET_REL" bash "$WT/$TARGET_REL/scripts/constraint-gates.sh" >"$WT/bite-N.log" 2>&1` — captured, so a failure can show its evidence before the worktree is removed (CTO).
2. **Pass.** rc must be 0. If not: when the log carries `error <rule>: ` lines → `verdict_fail 74 "N real client->server-secret violation(s) on HEAD newer than the merge-base baseline — the gate is live; fix the listed imports, then re-run"` listing them (a same-branch leak is exactly the not-grandfathered case, and it is not a broken gate — R3); otherwise `verdict_fail 71 "gate did not pass on the clean tree before the probe (rc=N) — config or toolchain error; see the log tail"`.
3. **Inject — each rule on the edge it exists for.** Under `$WT/$TARGET_REL/components/__constraint_scaffold_bite_probe__/`: `direct.tsx` (a `"use client"` module value-importing `@/server/__constraint_scaffold_bite_probe__`); `hop.ts` (a **non**-client helper in the probe dir that value-imports the same server module); `via-hop.tsx` (a `"use client"` module value-importing `./hop`); plus `server/__constraint_scaffold_bite_probe__.ts` exporting one string constant that is visibly not a secret. Four top-level scalar paths; no array; no `$( )`.
4. **Fail, naming both rules on their own edges.** rc must be non-zero **and** the log must contain a line matching `^\s*error no-client-to-server-secret: .*direct\.tsx` **and** a line matching `^\s*error no-client-to-server-secret-transitive: .*via-hop\.tsx` — else `verdict_fail 72 "the gate did NOT reject the injected client->server-secret import (rc=N; depcruise=<version>; rules named on their edges: <list>) — a gate that cannot fail is not a gate"`. Anchored on depcruise's `error <rule>: ` call-form on the captured stream, never a bare rule name (the runner's zero-reachability prose carries the bare token). The transitive line for `direct.tsx` may also appear (it does today) and is neither required nor forbidden.
5. **Revert.** Remove the four probe files.
6. **Pass again.** rc must be 0, else `verdict_fail 73 "gate did not return to green after the probes were removed (rc=N) — non-deterministic gate"`.
7. The helper removes the worktree. One verdict line on **stdout**: `constraint-scaffold: bite-proof pass -> fail(no-client-to-server-secret@direct, no-client-to-server-secret-transitive@via-hop) -> pass depcruise=<version>` — ASCII arrows so an AC can grep it; the version is read from `node_modules/dependency-cruiser/package.json`. No `SOLEUR_` literal.

**`verdict_fail <code> <msg>` (R13).** Prints `constraint-scaffold: bite-proof FAILED (<code>): <msg>` on **stdout**, then the last 40 lines of the relevant `bite-N.log` on stdout, then `die "$msg" <code>` (stderr, for the log). In **default mode**, before dying it removes every artifact this run emitted — `$CFG $RUNNER $WORKFLOW $FIXWORKFLOW_A $FIXWORKFLOW_B $BASELINE` (the script owns the list; the README and pointer have not been written yet), `rmdir`s `$TARGET/scripts` and `$TARGET/.github/workflows` when empty — and says so: *"removed the artifacts this run emitted; the repo is as it was (a SIGKILL may leave a stale registration: `git worktree prune`); re-run after fixing the cause"*. A failed first install is therefore re-runnable and never leaves a half-installed gate (R2). In refresh mode nothing is removed (the artifacts are committed) and the message says the baseline was rewritten and should be reviewed with `git diff`. The three-dirs precondition (65) routes its message through the same stdout path. **After a successful bite**, a failure inside `emit_readme`/`emit_pointer` (unwritable file, the symlink refusal below) is a **warning on stdout, not a fatal**: the gate is installed and proven; the message names the file and the missing doc, and the run exits 0 — prose is not the gate, and dying there would recreate the R2 class one step later (security-sentinel P2).

**Zero test seams (R11, specified from measurement R45).** The script honours no `CONSTRAINT_SCAFFOLD_TEST_*` variable. The suite drives every failure arm through a **fixture-owned stub `depcruise`** reached via the fixture's `apps/web-platform/node_modules` symlink (a symlink-of-symlink resolves — measured). The stub-prototype ran today's script and the emitted runner against such a stub and established the **branching table a stub must implement**, because three consumers parse three output types:

| argv contains | probe dir present in cwd | required stdout | rc |
|---|---|---|---|
| `--output-type baseline` (capture, cwd = merge-base worktree target) | n/a | `[]` — non-JSON here is written verbatim into the baseline and the runner then fails "not a JSON array" | 0, or the scaffold dies 68 **before** `prove_bite` |
| `--output-type json` (runner alias self-check, every green pass) | n/a | `{"modules":[]}` — non-JSON → `UNRESOLVED=-1` → runner rc 1 | 0 |
| `--output-type err`, no probe | no | `✔ no dependency violations found` (or the case's clean-arm text) | the case's clean-arm rc (0 for all but S-preprobe-violation) |
| `--output-type err`, probe present | `components/__constraint_scaffold_bite_probe__/direct.tsx` exists in cwd | the case's canned lines | the case's canned rc |

The stub discriminates the injected stage by a cwd-relative existence test (the runner `cd`s to the app dir), so no counter file is needed. Signature: `make_stub_depcruise <dir> <clean-out> <clean-rc> <probe-out> <probe-rc> [<kill-pid-file>]`; the stub also appends its argv to `<dir>/calls.log` and exits 64 on an argv shape it does not recognise (review-skill "stub only the binary, recording its argv"; work-skill "make the fake `exit 64` on a missing required flag"), and its `dependency-cruiser/package.json` carries the distinctive version `0.0.0-stub` so C1 can prove it ran the real toolchain. The smallest stub that yields a clean end-to-end run (scaffold rc 0, runner rc 0 — measured):

```bash
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/../calls.log"
case " $* " in
  *" --output-type json "*)     printf '{"modules":[]}\n' ;;
  *" --output-type baseline "*) printf '[]\n' ;;
  *" --output-type err "*)
    if [[ -e components/__constraint_scaffold_bite_probe__/direct.tsx ]]; then
      cat "$PROBE_OUT"; exit "$PROBE_RC"
    fi
    cat "$CLEAN_OUT"; exit "$CLEAN_RC" ;;
  *) exit 64 ;;
esac
```

(`PROBE_OUT`/`CLEAN_OUT`/rcs are baked into the generated stub by `make_stub_depcruise`.) S-term's stub runs `kill -TERM "$(cat "$PIDFILE")"` in the `err`-without-probe branch — the first `err` call is the pre-probe pass, after the trap is installed; the `baseline` call precedes it and must still return `[]`. Measured: the TERM is delivered while the scaffold is inside a foreground capture; bash defers the handler until the runner returns, the handler runs before the scaffold's next statement, and `exit 143` ends the run with the EXIT trap having removed the worktree. The C1/C8/C-e/C-warn cases point the symlink at the real `node_modules` instead. (`CONSTRAINT_SCAFFOLD_TEST_FORCE_EMPTY` in the emitted `.cjs` and `CONSTRAINT_SCAFFOLD_REPO_ROOT` remain what they are today — neither is added by this plan and the header says the script itself has no seams.)

Exit-matrix header gains 71/72/73/74. There is no residue class in the founder's tree. The refresh-mode invariant "agent-only; never shown to the founder" is unchanged.

### D7 — Refresh mode runs the bite-proof too, for config/runner drift — not for baseline poisoning

A probe is a brand-new origin, so no baseline entry can ever grandfather it (Premise table). What refresh-mode bite catches on the real target is drift no sentinel exercises there: a rule severity edited to `warn`, a from-set mis-scoped by a config edit, a runner that stopped failing on rc>0 (the case Guard 1's stub "both lines printed, exit 0" pins — R5). DHH argued install-time only (the config is agent-owned and parity-pinned); the issue text says "every scaffold run", the CTO's corrected rationale stands, and the cost is three runner passes plus one worktree pair on an agent-only path (Task 0.4 records the seconds). Recorded as a taste disagreement resolved toward the issue text (R39).

### D8 — README and pointer are append-once, written **last**, and carry no peer sentence

**Ordering (R1 — the P0).** `emit_readme()` and `emit_pointer()` run **after** `prove_bite()` succeeds, as the final writes before `exit 0` in default mode. `capture_baseline_mergebase()` re-runs the clean-tree guard on tracked files; appending to a tracked `CLAUDE.md` or an existing tracked `server/README.md` before it would dirty the tree, exit 67 with the executables already emitted, and leave the next run at 66 — on Soleur's own tree and on any founder repo with a tracked instructions file. Writing them last also means a 71/72/73/74 never has to undo them. Neither is written in refresh mode.

**Mechanism.** One helper, `append_once <file> <marker> <content>` — no repo precedent exists for a marker-keyed append into a user-owned file (precedent-diff: the repo's upserts are tempfile+`mv` replace-by-key), so the shape is prescribed literally: `[[ -L "$f" ]] && { warn "refusing to append through a symlink: $f"; return 1; }` first (a `CLAUDE.md -> ~/.claude/CLAUDE.md` link is a common founder shape and `>>` would write into their **global** instructions — CWE-59; security-sentinel); then `grep -qF -- "$marker" "$f" 2>/dev/null && return 0`; then `[[ -s "$f" && -n "$(tail -c 1 "$f")" ]] && printf '\n' >> "$f"` (the repo's only trailing-newline idiom, `git-data-cutover-access.test.sh`); then `printf '%s\n' "$content" >> "$f"`. The same symlink refusal guards `server/README.md`. README block markers: `<!-- constraint-scaffold:readme:start -->` … `<!-- constraint-scaffold:readme:end -->`; pointer marker: `<!-- constraint-scaffold:pointer -->` at the end of the one line. The refuse-if-exists invariant protects **executable** gate artifacts; prose gets append-once (CTO). **Pointer file: `$REPO_ROOT/CLAUDE.md` if present, else `$REPO_ROOT/AGENTS.md` (created if absent)** — two arms (R32). The pointer text is plain, **informational** prose with a repo-relative path — `The client/server import boundary and its CI gate are documented in apps/web-platform/server/README.md (generated by soleur:constraint-scaffold). <!-- constraint-scaffold:pointer -->` — not an imperative "read X before Y", because an imperative pointer promotes a tracked, unpinned markdown file in a founder repo to de-facto agent instructions (OWASP LLM01; security-sentinel); **never** `@apps/…`. The README block's first line says it is generated and agent-owned, like the config.

**Content (Soleur-authored; no peer sentence).** What the boundary is (a `"use client"` module must not take a value import — direct or transitive — on `server/**`); the two rule names; `import type` as the permitted shape; how to run the gate (`bash scripts/constraint-gates.sh` from `__TARGET_DIR__`); the requirement that `app/`, `components/`, `server/` exist and `@/*` resolves; **what the founder actually sees when the gate trips — a red check on the PR and, when auto-fixable, an ADR-074 draft follow-up PR to merge** (spec-flow: not the runner header's "blocks the merge"); that the scaffold proved the gate bites on install over the committed tree (pass → fail → pass) and how to re-prove with `--refresh-baseline`; and the agent-owns-recovery rule (the founder never edits `.dependency-cruiser.cjs` or the baseline).

**Attribution.** `references/boundary-readme.template` (in Soleur's distribution) carries the `setup-ts-deep-modules` comment on its first line, because its *shape* — README next to the governed path plus an instructions pointer — is the peer's step 7. `emit_readme()` strips that first line (the one beginning with the HTML-comment opener and `Inspired by`) on emission with an inline `sed -e '1{/^…Inspired by /d}' -e "s|__TARGET_DIR__|$TARGET_REL|g"` (the exact expression is in the script; it is not quoted here because a bare comment opener in prose defeats preflight's HTML-comment scrubber and hides the `## User-Brand Impact` heading below from Check 6 — measured at ship) (no shared `.sed` file — R9; `parity.test.sh` pins the literal expression by grep). The emitted README shares **no sentence** with the peer file: AC2 runs an 8-word shingle comparison between the emitted README and the pinned peer blob and requires **zero shared shingles** (an intersection count, not the Jaccard ratio), using the same normalisation as the repo's existing originality scorer — lowercase, `[^a-z0-9\s]+` → space, `SHINGLE_N = 8` (`plugins/soleur/test/agent-originality.test.ts` › `neutralize()` / `shingles()`), so the two shingle definitions in the repo agree (CPO b1, CMO, precedent-diff). Under that condition the operator's constraint ("every file taking peer prose") does not reach the emitted file by content, and constitution line 192 (vendored credit stays in the corpus, stripped from emitted user output; MIT is satisfied by `plugins/soleur/NOTICE` in Soleur's distribution) is the default. If a peer sentence ever survives into the README, the default flips: keep the comment. This reading is recorded in `decision-challenges.md` for `ship` to surface (R30), with the revert cost named: one `sed` expression, parity row 7 and the dogfood file, in one commit.

### D9 — Dogfood parity: the emitted README and the pointer exist in Soleur's own tree, pinned by `parity.test.sh` rows 7–8

`constraint-scaffold.sh` refuses to re-run against `apps/web-platform` (artifacts exist), so the two new artifacts are placed by hand and pinned: `apps/web-platform/server/README.md` must be non-empty and byte-equal to the emitter's transform of the template (row 7 — `[[ -s ]]` first, then `diff`; a `diff` of two empty operands passes, which is the parity vacuity that matters — CTO), and repo-root `CLAUDE.md` must be non-empty and carry the pointer marker exactly once, on a line naming `apps/web-platform/server/README.md` and containing no `@apps/` (row 8). The suite gains an independent `cases` counter, a conservation check and a `MIN_ROWS=10` floor in the shape `guard-vacuity-floor.test.sh` recognises (R36).

### D10 — ADR-071 amendment for the scaffold contract; new ADR-230 for the marker taxonomy; no C4 change

- **ADR-071 amendment** `## Amendment 2026-09-19 (#8288) — install-time bite-proof, README and agent-instructions pointer`. Decision: the both-modes bite; exit codes 71/72/73/74; worktree isolation through the shared helper; default-mode self-cleanup on failure; the precondition on the three dirs; README/pointer append-once written last. **Consequences it must record** (architecture-strategist, CPO — R23): (a) the first scaffold write outside `$TARGET` (repo-root `CLAUDE.md`/`AGENTS.md`), and that in Soleur's own tree this is the first product-specific line in a file that was `@AGENTS.md`; (b) the refuse-if-exists exception class — prose artifacts are append-once and marker-keyed; executables stay refuse-only, and why; (c) refresh mode now exits non-zero (74) on a real HEAD violation newer than the baseline; (d) the bite proves HEAD plus the copied artifacts under `CONSTRAINT_GATES_DIR`, not the CI path's `dirname BASH_SOURCE/..` derivation; (e) two sequential worktree adds per run and the measured cost; (f) the P1b baseline delta and the parity rows. Alternatives: in-place probe; CI-time bite; refuse-if-exists README; direct-rule-only assertion; an opt-out flag for the bite (rejected — a gate you can skip proving is the class the issue names).
- **ADR-230** (provisional ordinal) *"Temporary debug probes are `[DEBUG-<hex4>]`, never `SOLEUR_*` sentinels"* (~30 lines): Context (the permanent class is defined only by its enforcement — `MARKER_RE` + the drift guard — and had no removable counterpart); Decision (the **single normative** two-class table: spelling, lifetime, readers, decision rule, cleanup, the never-`SOLEUR_` rule, the placeholder discipline); enforcement sites (the three prose gates and Guard 4's two predicates); the label route's reach (Soleur's digest today); Alternatives (prefix grep; diff-scoped grep; folding into ADR-071 — rejected: wrong home, a third consumer must find it). Ordinal re-derived across every `origin/*` ref immediately before merge; a renumber sweeps this plan, `tasks.md`, the ADR file and the two SKILL.md citations in one edit.

C4: no view changes. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`): the actors and systems touched — the founder's repo, GitHub Actions on it, dependency-cruiser, the Soleur plugin on the founder's CLI, the `MARKER_RE` extractor — are the set the L1 gate and the git-lock telemetry already modelled; no external human actor, vendor, container, data store or access relationship is added. AC19 runs `plugins/soleur/test/c4-count-parity.test.sh` to back this against the derived cardinalities the rubric cannot see.

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) a `reproduce-bug` run that stalls at the new Phase 2 gate on a bug where no loop is buildable and, instead of stopping and saying so, keeps searching — burning the founder's API budget on their own bug; (b) a `constraint-scaffold` first install that exits 71/72 and leaves five executable artifacts behind, so every re-run says 66 and the founder's agent has no path back — the incident R2 removes; (c) a seam-absence finding that labels an issue in a repo where the label does not exist, so the `gh` call fails and the finding never reaches anyone — the incident R28 removes.
- **If this leaks, the user's diagnostic data is exposed via:** the redacted command output the new Phase 8 asks to paste into a GitHub issue comment — a loop built with a raw token in argv would put the credential in a public issue. Vector: issue comment. Control: the imported "Redact" paragraph (loops against env vars; `<REDACTED>` in every shown output; quote only the lines carrying the signal) sits at the top of Phase 2, before any command is shown.
- **If this leaks, the user's source layout is exposed via:** nothing new — the README describes the boundary, not the tree, and the pointer names one path.
- **Brand-survival threshold:** `single-user incident` — one founder whose scaffold refuses to install, or whose issue comment carries a token, is the brand.

Controls carried into the implementation: the bite-proof's four failure arms each name **which** step failed, what to do, and (in default mode) that the repo was restored; the worktree isolation removes the residue class entirely; Phase 2's "cannot build a loop" arm is a **stop** with defaults, so (a) is a bounded exit not a loop; a founder-repo `tsconfig` without `@/*` presents as 71 with the runner's own alias-check message and the log tail, not as a mysterious 72. `user-impact-reviewer` runs at review time (single-user-incident threshold).

### Addendum — 2026-09-19 review of PR #8352 (nine-seat panel)

The panel measured six user-facing failure modes the section above did not name; each is now closed in the implementation and recorded here so the section stays a true map:

| Artifact | Vector | Closed by |
|---|---|---|
| Five executables in the founder's repo | merge-base 69 (default branch `master`, no remote, `origin/main` unfetched) or an unusable `TMPDIR` fired **after** the emits and **before** any trap → residue, every re-run 66 | base ref (`origin/main`, else `origin/HEAD`) and `TMPDIR` containment resolved before the first write; cleanup armed before the first write, disarmed after `prove_bite`; S-noorigin / S-originhead / S-mktemp rows |
| Same six artifacts | terminal Ctrl-C reaches the node child (rc 130) and was dispatched as a 72 verdict; SIGKILL residue had no recovery text | runner propagates 130 as an interrupt; scaffold treats it as such; the 66 message names the killed-install recovery (only SIGKILL can leave residue — the "at most a stale registration" sentence in §Observability was false and is superseded by this row) |
| A correct install rolled back as 72 | `FORCE_COLOR=1` in the environment decorates depcruise's `error <rule>:` lines, both anchors match nothing; a real leak read 71 instead of 74 | runner exports `NO_COLOR=1`; scaffold strips ANSI before the anchors; S-ansi + C1-color rows |
| Phase 8 comment fields 1/2/6/7 | opaque `Authorization: Bearer …`, non-vendor `DATABASE_URL=`, internal hostnames, customer names/phones pass `redact-engine.py` rc 0; screenshots never pass through it | Phase 1 states the redactor's ceiling; Phase 8 adds a structural header/query-string grep before the redactor, a screenshot PII rule, and posts via the fail-closed `redact-sentinel.sh` shim |
| Founder-supplied HAR / recording | storage location unspecified (lands in the repo), strip list omitted `queryString`/`content.text`/`_webSocketMessages`/response cookies, no mechanical Phase 9 check, then `test-fix-loop`'s `git add -A` commits it | `mktemp -d` outside the repo, complete strip list, Phase 9 + test-fix-loop untracked-artifact grep |
| Founder's stdout on 65(next.js)/66/67/68/70 | stderr-only; the 65 message did not name the missing dir | `die` prints on stdout first for every code; 65 names the dir |

From the coverage consult (the question "which class is absent"), verified against the script and closed: GNU-only tools (`realpath -m` ×3, `sed -i` + `\x1b`, `1{…d}`) would abort with exit 1 and empty stdout on stock macOS — replaced with POSIX spellings (`pwd -P`, `sed … > tmp && mv`, `d;}`); `git worktree add` and depcruise stderr were discarded before the 68/69 message — now carried; a shallow clone's merge-base failure is named; two concurrent runs in one repo (default + refresh) could delete each other's staged inputs — a `mkdir` run lock with owner pid, S-lock rows; the new suites now source `git-fixture-env.sh` (a developer `commit.gpgsign` reached 20+ fixture commits). Not changed: hooks still run inside `worktree add` (same trust domain as `git checkout`; disabling them would also disable LFS smudge).

Not a user-facing vector but recorded: Guard 4's second predicate missed the pino `log.warn({ SOLEUR_X_DEBUG: true })` form (the tree's dominant marker shape) and `echo '…'`; widened with eleven in-suite positive controls.

## Infrastructure (IaC)

Not applicable. No server, secret, vendor, DNS, cron or persistent runtime is introduced; every deliverable is plugin prose, one shell script, its tests, one template, two dogfood files and two ADR artifacts.

## Observability

Layer **7 — `cli-stdout-artifact`** (`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`, layer-7 paragraph). The scaffold runs on the founder's own machine; routing its output to Soleur infrastructure is a data-controller event, not an observability improvement, so Sentry/Better Stack are deliberately **not** wired. Soleur's own CI runs the suites (layer 6, workflow run log). **Layer-7 durable-artifact pairing, stated honestly:** the durable half is the committed gate itself (the emitted workflow re-runs the runner on every PR) and the README; the README is byte-pinned to a static template, so it cannot carry the verdict's fields, and a 71–74 in default mode leaves nothing durable by design (the run restores the tree). Those verdicts are **transcript-only**, and the refresh-mode verdict is re-runnable on demand — this is a recorded deviation from the layer's "same fields in a committed artifact" rule, accepted because the alternative (a `__BITE_VERDICT__` token substituted into the README) would make parity row 7 normalise a per-run line and turn a doc into a log.

```yaml
liveness_signal:
  what: >
    The scaffold's exit code and its stdout verdict line
    ("constraint-scaffold: bite-proof pass -> fail(<rule>@direct, <rule>@via-hop) -> pass depcruise=<v>").
    The durable half is the committed gate itself: the emitted CI workflow runs the runner on every
    PR, and the README the scaffold emits documents the bite-proof next to the governed tree.
  cadence: once per scaffold run; the emitted workflow re-runs the gate on every PR
  alert_target: >
    none - deliberately. Founder's machine; no telemetry export without consent (layer 7).
  configured_in: plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh (prove_bite, verdict_fail)
error_reporting:
  destination: >
    stdout: "constraint-scaffold: bite-proof FAILED (<code>): <msg>" plus the last 40 lines of
    the captured runner log, then the same message on stderr via die(). Codes: 71 pre-probe
    config/toolchain failure, 72 probe not rejected or rule not named on its edge, 73 post-revert
    failure, 74 real HEAD violations newer than the baseline. STDOUT because agent runtimes surface
    stdout and swallow stderr (provision-doppler.sh:12-13).
  fail_loud: true
failure_modes:
  - mode: the gate cannot reject the probe (alias resolution broken, runner neutered, severity softened)
    detection: bite-proof exit 72 with the rule names seen per edge and the log tail; alias breakage surfaces earlier as 71 with the runner's own message
    alert_route: local, layer 7 cli-stdout-artifact - the scaffold refuses to report success and (default mode) removes what it emitted
  - mode: a same-branch leak newer than the merge-base baseline
    detection: exit 74 listing the violating imports - the gate is live, the bite is unprovable until they are fixed
    alert_route: local, layer 7 cli-stdout-artifact
  - mode: interrupted run (TERM) or worktree left behind
    detection: >
      the shared helper's INT/TERM handler removes the worktree AND (default mode) the six emitted
      artifacts, prints "interrupted; removed: <list>" on stdout and exits 143; a SIGKILL leaves a
      mktemp dir under TMPDIR (never inside the repo - a TMPDIR inside the repo is refused) and at
      most a stale .git/worktrees registration, cleared by git worktree prune, which the 68/71
      recovery text names
    alert_route: local, layer 7 cli-stdout-artifact, bounded
  - mode: a temporary [DEBUG-<hex4>] probe ships in a fix
    detection: the shape grep (with --untracked) at reproduce-bug Phase 9, test-fix-loop (pre-checkpoint and pre-stage) and ship's pre-PR checklist prints a line; in Soleur's own tree plugins/soleur/test/debug-probe-residue.test.sh fails CI
    alert_route: local (layer 7 cli-stdout-artifact) for a founder repo; layer 6 workflow run log for Soleur
  - mode: a probe is mis-spelled as a SOLEUR_* marker
    detection: >
      two layers - the drift guard in apps/web-platform/test/git-lock-marker-telemetry.test.ts
      collects echo/printf literals from skills/*/scripts/*.sh wholesale and from SKILL.md only for
      in-domain names (DOMAIN_RE), and never scans apps/** or plugins/soleur/test/**; Guard 4's
      second predicate catches an EMITTED SOLEUR_*DEBUG* spelling (echo/printf/console.* call-form)
      anywhere in the tracked tree, including apps/web-platform/** where a console.log would be
      typed, while leaving the legitimate env flag SOLEUR_DEBUG_PERMISSION_LAYER alone
    alert_route: layer 6 workflow run log (CI)
  - mode: dogfood README or pointer drifts from the template, or is empty
    detection: parity.test.sh rows 7-8 (-s checks, then diff / grep) in the scripts shard
    alert_route: layer 6 workflow run log (CI)
  - mode: the scaffold runs on the HOSTED agent runner (plugins/soleur/ is vendored into the prod image) and fails 71-74
    detection: >
      transcript exit code only - by design in this PR no SOLEUR_* literal is emitted (AC13, the
      operator's marker-population caution), so no telemetry layer sees it. Recorded as Deferral 3:
      a mirrored-not-paged SOLEUR_CONSTRAINT_SCAFFOLD_HALT registered in MARKER_RE (inside the
      drift guard's _HALT$ domain) is the follow-up, not a silent gap
    alert_route: none today (declared); layers 2/3 (pino -> Sentry breadcrumb; journald -> Vector -> Better Stack) via the marker extractor after Deferral 3 (#8381)
logs:
  where: >
    the founder's terminal / agent transcript for the scaffold run; Soleur plugin-CI logs for
    the hosted suites. No new sink.
  retention: session-scoped locally; CI log retention for the hosted runs
discoverability_test:
  # Amended at ship (2026-09-19): the bite-proof suite (~40 s with the real toolchain) exceeds
  # preflight Check 10's 15 s sandbox cap, so it would report a timeout, not the property. The
  # parity suite pins the same layer-7 artifact claim in ~2 s with no network: template ==
  # dogfood, README block == emitter transform, pointer once, emission census. bite-proof itself
  # runs in CI's scripts shard on every PR.
  command: bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh
  expected_output: "parity.test.sh: 12 passed, 0 failed (12 rows)"
```

First token `bash`, second a repo-relative path: satisfies preflight Check 10's `PROBE_VERB_ALLOWLIST`. No `credentials_required` declaration is needed.

### Soak Follow-Through Enrollment

Not applicable. No acceptance criterion is time-gated.

## Encryption Posture

Not applicable — no persistent store and no new cross-component connection.

## Architecture Decision (ADR/C4)

### ADR

1. Amend **ADR-071** (`knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md`) as D10 specifies, mirroring the 2026-07-01 amendment's shape. Via `soleur:architecture` in Phase 6.
2. Create **ADR-230** (provisional) as D10 specifies. Ordinal re-derived across all `origin/*` refs before merge.

### C4 views

No view changes — see D10 for the actor / system / relationship enumeration against all three `.c4` files. AC19 is the mechanical backing.

### Sequencing

Both ADR artifacts land in this PR (Phase 6); nothing is soak-gated.

## Guard Contract

Four guards. Each matrix is derived from the design, written before the guard, and every RED row is executed in the work phase with the observation recorded (AC20). Axes, as the operator required: **SUT** (the guard's own code), **fixture shape** (what the input looks like), **fixture direction** (must-FAIL vs must-PASS input), **dispatch** (does the guard run at all / over the right set), **cardinality** (first member vs a second member).

### Guard 1 — the install-time bite-proof (`prove_bite()` in `constraint-scaffold.sh`)

**Property.** After every scaffold run that reports success, the emitted gate has been observed on a detached worktree of the target's HEAD to (i) pass without the probes, (ii) reject a direct `"use client"` value import of `server/**` naming `no-client-to-server-secret` on that edge **and** a one-hop chain naming `no-client-to-server-secret-transitive` on that edge, and (iii) pass again with the probes removed — the founder's tree is untouched, and a run that cannot prove it (default mode) leaves the repo as it found it.

**Assembly.** The chokepoint is `prove_bite()`, and the property quantifies over **both** mode exits: the default mode's tail and the refresh mode's tail (the two `exit 0` sites). It reads the runner through the emitted `scripts/constraint-gates.sh` in the worktree (the one pinned invocation from `shared-runner.template`, under its own `CONSTRAINT_GATES_DIR` override), captured `2>&1` to a file; the two rule names as literals that the suite pins equal to the `name:` fields in `depcruise-config.template` (a rename reds there); and exactly four probe paths bound as top-level scalars. The rule set is a fixed pair by design (single-boundary scope), so discovery is a parity pin, not a census. The self-cleanup list on failure is the script's own emitted-artifact variables, so a new artifact cannot be left behind without also being left out of the list — the suite pins that list against the refuse-if-exists loop's list.

**Mutation matrix.** 14 rows (1–12 plus 3b, 3c). Each row MUST drive `bite-proof.test.sh` RED. Stub cases are driven by the fixture-owned stub `depcruise` (no production seam); every stub named below is the `err`+probe-present arm (or, for S-preprobe-violation, the `err`+probe-absent arm) of an otherwise-clean three-branch stub (D6).

| # | Axis | Mutation | Why |
|---|---|---|---|
| 1 | dispatch | Delete the `prove_bite` call from the **refresh** tail only | A guard scoped to one of two exits is the #7493 class; C6 (refresh run's verdict line) reds |
| 2 | dispatch (own) | Replace `prove_bite()`'s body with `return 0` | "0 checked, exit 0" — C1's verdict-line and every stub case's exit-code assertion red |
| 3 | SUT | Drop the `-transitive` assertion from step 4 | Stub S-direct-only (prints only the `direct.tsx` direct-rule line, rc 1) must yield 72 today; under this mutation it passes → RED |
| 3b | SUT / cardinality | Delete `hop.ts` from the injected set | Real run C1: `via-hop.tsx` no longer reaches `server/**` → the transitive line for it is absent → 72 — proves the transitive assertion is tested on the edge it exists for |
| 3c | anchor | Assert the transitive rule on `direct.tsx` instead of `via-hop.tsx` | Stub S-real-minus-direct-transitive (today's real output minus the direct-edge transitive line — the shape a reachability-semantics change would produce) must still pass; under this mutation it yields 72 → RED |
| 4 | SUT | Delete the revert (step 5) | Real run C1: step 6 fails → 73 |
| 5 | SUT (order) | Move the `trap` install below `worktree add` in the shared helper | Source-shape pin: inside `with_detached_worktree` the line matching `trap '_wt_cleanup` must precede the line matching `worktree add --detach` (an `awk` order assertion on a **specific** trap, so a `trap - EXIT` line cannot satisfy it — test-design). Behavioural twin, run only when not root: `chmod a-w "$FX/.git"` makes `worktree add` fail → `die … 69` must leave no `mktemp` dir — this fails exactly when the trap is installed after the add. S-term separately proves the handler removes the worktree and exits 143, but does not discriminate ordering (the TERM arrives after both) |
| 6 | fixture shape | Probe dir under `lib/` instead of `components/` | Outside the cruise roots → gate cannot see it → 72 in C1 |
| 7 | fixture direction | Delete the rc check in step 4 | Stub S-lines-rc0 (prints **both** call-form lines on their edges and exits 0 — the "runner stopped failing on rc>0" drift D7 names) must yield 72 today; under this mutation it passes → RED. Real twin C-warn (a copied `.cjs` with one rule at `severity: "warn"` → `warn <rule>: …`, rc 0) must yield 72 with the real toolchain and proves the `^\s*error ` anchor rejects a `warn` line |
| 8 | dispatch (precondition) | Delete the three-dirs precondition | A fixture with no `components/` must exit 65 before emission; under this mutation it emits and then dies 71 with artifacts on disk → RED |
| 9 | anchor | Assert on the bare token `no-client-to-server-secret` instead of the `^\s*error <rule>: ` call-form on the named file | Stub S-bare-tokens (prints one line carrying both bare rule names and both probe filenames without the call-form, rc 1) must yield 72 today; under this mutation it passes → RED |
| 10 | SUT | Copy only `$CFG` into the worktree, not `$BASELINE` | The runner's "baseline missing" arm fails the pre-probe pass → 71 in C1 — proves the worktree carries the same three artifacts the target does |
| 11 | SUT (cleanup) | Delete one path from the default-mode failure-cleanup list | Stub S-fail72 in default mode must leave `git status --porcelain` empty; under this mutation one artifact survives → RED |
| 12 | SUT (74 split) | Collapse 74 into 71 | Stub S-preprobe-violation (pre-probe pass prints a real `error <rule>: ` line for a non-probe file, rc 1) must yield 74 listing the file; under this mutation it yields 71 → RED |

**Harness rows.** (a) Delete the `cases=$((cases + 1))` at C1's call site only → the conservation check reds (`pass+fail != cases`). (b) Stub `bad()` to a no-op → conservation reds first (ADR-193 #4). (c) Delete every assertion after the toolchain probe → the `MIN_ASSERTIONS` floor reds via `printf >&2; exit 1`, not via `bad()`. (d) **Must-PASS non-canonical:** a fixture whose `components/` already contains an unrelated `"use client"` module with a **type-only** server import and a committed baseline with one **direct** value-safe entry — the bite-proof must still report pass → fail(both) → pass. (e) **Must-PASS non-canonical:** a fixture with a **committed** `CLAUDE.md` and a **committed** `server/README.md` — default mode must succeed and append once to each (this is the fixture that would have caught the P0). (f) **Real-not-stub proof:** C1 asserts the verdict's `depcruise=` value equals the version in the real `node_modules/dependency-cruiser/package.json` and is not `0.0.0-stub` — a probe-aware stub prints exactly the lines C1 expects, so without this row a mis-pointed symlink would pass C1 silently (test-design). (g) **Refusal rows:** a symlinked `CLAUDE.md` → pointer refused, nothing written through the link, run exits 0 with the warning; `TMPDIR` set inside the fixture repo → exit 69 before any worktree is created.

**Anchor.** The guard compares the runner's live behaviour to two rule-name literals in the same repo, so one diff could rename both. The outside anchors are `parity.test.sh` + `boundary.test.sh` (template ↔ emission ↔ real FAIL/PASS on synthesized fixtures) and depcruise's own `error <name>: ` output format, which no Soleur commit controls.

### Guard 2 — template ↔ dogfood parity for the README and the pointer (`parity.test.sh` rows 7–8)

**Property.** `apps/web-platform/server/README.md` is non-empty and byte-identical to the emitter's transform of `boundary-readme.template` (first-line attribution stripped, `__TARGET_DIR__` substituted), and repo-root `CLAUDE.md` is non-empty and carries the pointer marker exactly once, on a line naming `apps/web-platform/server/README.md` and containing no `@apps/`.

**Assembly.** Row 7: `[[ -s "$APP/server/README.md" ]]`, then the same `sed | diff` chokepoint the existing rows use with the emitter's literal expression (which the row also pins by `grep -cF` against the script — one transform, two copies, a grep that reds when they diverge). Row 8: `[[ -s CLAUDE.md ]]`, `grep -c -- '<!-- constraint-scaffold:pointer -->' CLAUDE.md` == 1, that line contains the README path, that line does not contain `@apps/` — four selections for a four-dimension claim.

**Mutation matrix.** Each row MUST drive `parity.test.sh` RED.

| # | Axis | Mutation | Why |
|---|---|---|---|
| 1 | SUT | Edit one word in the dogfood README | Row 7 red |
| 2 | SUT | Edit one word in the template | Row 7 red — parity is symmetric |
| 3 | fixture shape | Truncate the dogfood README to zero bytes | Row 7 red on `-s` — a `diff` of two empties would have passed |
| 4 | dispatch | Delete the pointer line from `CLAUDE.md` | Row 8 red |
| 5 | cardinality | Append the pointer line a second time | Row 8 red — `== 1`, not `>= 1` |
| 6 | fixture direction | Pointer line present but naming a different path | Row 8 red |
| 7 | fixture direction | Pointer written as `@apps/web-platform/server/README.md` | Row 8 red — the import form is forbidden |
| 8 | SUT | Change the strip expression in the script but not in the test | Row 7's `grep -cF` pin red |

**Harness rows.** Stub `fail()` → the retrofitted conservation check reds (independent `cases` counter); must-PASS non-canonical: a template change landing together with a regenerated dogfood copy passes (parity is symmetric, not pinned to today's bytes).

**Anchor.** The template anchors the dogfood copy; the template is anchored by Guard 1's use of the README path and by the ADR-071 amendment text.

### Guard 3 — the `[DEBUG-<hex4>]` cleanup gate as prose (`reproduce-bug` Phase 9, `test-fix-loop` pre-checkpoint + pre-stage, `ship` pre-PR)

**Property.** No tracked line outside `knowledge-base/` carries a real tag, at the moment a probe could otherwise be committed or shipped.

**Assembly.** `git grep -niE --untracked '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'` — every tracked **and untracked** file, every line, either case, binaries included; run at the three sites D4 names, of which `test-fix-loop`'s pre-checkpoint site is the one that stops a probe from ever being committed (architecture-strategist: the success-row grep alone left the per-iteration checkpoint commit as an uncovered injection site; security-sentinel: without `--untracked` that site was blind to the most likely file).

**Mutation matrix** (executed on a scratch branch in the work phase; observations to the PR body).

| # | Axis | Mutation | Expected |
|---|---|---|---|
| 1 | fixture direction | Add `console.log("[DEBUG-3f9c] x")` in a `.ts` file | One line printed (RED) |
| 2 | cardinality | A second probe in another file | Two lines printed |
| 3 | dispatch / must-PASS | The two SKILL.md files and ADR-230, which contain the placeholder `<hex4>` and the regex itself | Nothing printed (GREEN) |
| 4 | fixture direction | A hand-typed uppercase tag `[DEBUG-3F9C]` | One line printed — the grep is case-insensitive |
| 5 | dispatch (site) | Walk `test-fix-loop`'s §4 with a probe present: the pre-checkpoint grep must fire before `git commit … checkpoint` | The checkpoint is never created with the probe in it |
| 6 | fixture shape | The probe lives in an **untracked** `.ts` file (never `git add`ed) | One line printed — `--untracked` is what makes row 5 true; without it the grep is silent (measured) |
| 7 | fixture shape | A `.ts` file containing one NUL byte (git classifies it binary) carrying a real tag | `Binary file … matches` printed — non-empty output is the property; `-I` would have hidden it (measured) |

**Anchor.** The shape is fixed by the mint command in the same prose; Guard 4 is the mechanical twin.

### Guard 4 — `plugins/soleur/test/debug-probe-residue.test.sh` (Soleur CI)

**Property.** No tracked file outside `knowledge-base/**/*.md` in Soleur's own tree contains a real `[DEBUG-<hex4>]` tag (either case) or **emits** a `SOLEUR_[A-Z_]*DEBUG` marker.

**Assembly.** Two predicates over one derived population, run from `git -C "$ROOT" rev-parse --show-toplevel` (the pathspec is cwd-relative — test-design): `git grep -liE '\[DEBUG-[0-9a-f]{4}\]' -- . ':!knowledge-base/**/*.md'` and `git grep -lE '(echo "|printf .|console\.(log|debug|warn|error)\(["'"'"'`])SOLEUR_[A-Z_]*DEBUG' -- . ':!knowledge-base/**/*.md'` — the second is narrowed to the **emit call-form** because the bare token is red on today's tree (`SOLEUR_DEBUG_PERMISSION_LAYER`, a legitimate env flag read in `apps/web-platform/server/permission-log.ts` and its test — measured; the call-form predicate matches 0 files today) and it closes the gap the drift guard's `SENTINEL_RE` leaves at the realistic injection site (R22). No `-I` (binary heuristic false negatives — measured). **Predicates run first and print every finding; the floor runs last**, so a RED row is observable by the named path on stdout, not only by rc. `$ROOT` is the suite's first argument (default: its own repo) and `MIN_POPULATION` its second (default 2 500, derived from 5 168 today), so RED rows run against **synthesized** throwaway repos with `MIN_POPULATION=1` (`cq-test-fixtures-synthesized-only`) and the must-PASS rows run against the real tree. The suite also carries a three-row `cases` counter (predicate 1, predicate 2, population) with `MIN_CASES=3` in the meta-guard's recognised shape plus the conservation check, so it is classified by `guard-vacuity-floor.test.sh` and AC16 holds (test-design). `git grep -l` exits 1 on no match, which is the clean verdict (measured).

**Mutation matrix.** Each RED row MUST drive the suite RED; rows 5 and 7 MUST stay GREEN.

| # | Axis | Mutation | Expected |
|---|---|---|---|
| 1 | fixture direction | Synthesized repo with a `.ts` carrying a real tag | RED, naming the file |
| 2 | cardinality | Two such files | RED, both named |
| 3 | dispatch (own) | Point `$ROOT` at an empty synthesized repo | The population floor reds via `printf >&2; exit 1` |
| 4 | SUT | Widen the first regex to the prefix `\[DEBUG-` | RED on the two SKILL.md files in the real tree — proves the shape, not the prefix, is enforced |
| 5 | must-PASS | A learning under `knowledge-base/` quoting `[DEBUG-3f9c]` (real tree) | GREEN — the exclusion is deliberate |
| 6 | fixture direction | Synthesized file carrying `[DEBUG-3F9C]` (uppercase) | RED — case-insensitive |
| 7 | must-PASS | The real tree today — including `apps/web-platform/server/permission-log.ts` (`process.env.SOLEUR_DEBUG_PERMISSION_LAYER`, a read, not an emit) | GREEN — and the trailer prints the population count (5 168 today) |
| 8 | fixture direction | Synthesized `apps/x.ts` with `console.log("SOLEUR_DEBUG_x")` | RED on the second predicate, naming the file |
| 9 | dispatch | Delete the second predicate | Row 8's fixture passes → RED |
| 10 | fixture direction | Synthesized `apps/y.ts` with `const flag = process.env.SOLEUR_DEBUG_Y` (a read) | GREEN — the boundary between env flag and emitted marker is pinned |

**Harness rows.** (a) Stub `bad()` to a no-op → the conservation check (`pass+fail != cases`) reds first. (b) Delete the `MIN_CASES` floor → `guard-vacuity-floor.test.sh` reports the suite as having left its population (the population floor's operand is a `wc -l` value, not an incremented counter, so it is not what the meta-guard classifies — the `cases` floor is).

**Anchor.** `git ls-files` is the index, outside any one file's control; the floor's operand is the index size.

## Files to Create

| Path | Role |
|---|---|
| `plugins/soleur/skills/constraint-scaffold/references/boundary-readme.template` | The README block emitted to `<target>/server/README.md` (`__TARGET_DIR__` substituted; first-line attribution comment stripped on emission). Markdownlint-clean once transformed. No peer sentence (AC2 shingle check). |
| `plugins/soleur/skills/constraint-scaffold/test/bite-proof.test.sh` | Hermetic end-to-end suite for D6/D8: throwaway git repo with `refs/remotes/origin/main`, an `apps/web-platform`-shaped Next.js app (`next.config.js`, anchored `"next"` dep, `tsconfig.json` with `@/*`, `app/`, `components/`, `server/`), a `node_modules` symlink pointing at the real toolchain (locate-or-install block copied from `boundary.test.sh`) **or** at a fixture-owned stub dir per case, committed, run under `CONSTRAINT_SCAFFOLD_REPO_ROOT`. ADR-193 floors in the shape the meta-guard recognises. Auto-registers on `plugins/soleur/skills/*/test/*.test.sh`. |
| `plugins/soleur/test/debug-probe-residue.test.sh` | Guard 4. Auto-registers on `plugins/soleur/test/*.test.sh`. |
| `apps/web-platform/server/README.md` | Dogfood emission of the template (D9). |
| `knowledge-base/engineering/architecture/decisions/ADR-230-temporary-debug-probes-are-debug-hex4-never-soleur-sentinels.md` | D10 (provisional ordinal). |

## Files to Edit

| Path | Edit |
|---|---|
| `plugins/soleur/skills/reproduce-bug/SKILL.md` (14 463 B today) | Attribution comment on the first line after the frontmatter close and **before** the `soleur-cloud-mode:start` line (R27). D1 restructure: Phases 2, 4, 5, 6 new; 1, 3, 7, 8, 9 amended as tabled. `description:` unchanged. |
| `plugins/soleur/skills/test-fix-loop/SKILL.md` (9 469 B) | Attribution comment, same placement. Phase 0: the `--cmd` / `--max` argument form in `schedule/SKILL.md`'s existing phrasing ("If `$ARGUMENTS` contains `--cmd` … extract values directly … Optional flag: `--max` (iterations, default 5)" — say "iterations" so it never reads as `schedule`'s `--max-turns`) and the reproduce-bug hand-off sentence. Phase 1 §4: the shape grep **before the checkpoint commit** and before the success-row `git add -A` (D4). Diagnostic Report › Recommendation: the `legacy-code-expert` routing (D5). Key Principles: one bullet "Probes are not fixes — a `[DEBUG-<hex4>]` line never checkpoints or stages (ADR-230)". `description:` unchanged. |
| `plugins/soleur/skills/constraint-scaffold/SKILL.md` (7 791 B) | Attribution comment. New `## Bite-proof (every run)` section (the steps, exit codes 71–74, worktree isolation, default-mode self-cleanup and the recovery path, the three-dirs precondition); `## What it emits` gains `server/README.md` (append-once block, written last) and the pointer row; `## Usage` notes refresh mode also proves bite and may exit 74; `## Self-tests` gains `bite-proof.test.sh`. |
| `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` (181 L) | Header exit matrix (+71/72/73/74; "no test seams" note); attribution comment; three-dirs precondition; `with_detached_worktree()` (R33) with `capture_baseline_mergebase()` refactored onto it; `append_once()`, `emit_readme()`, `emit_pointer()` called **after** `prove_bite()` in default mode; `verdict_fail()` with default-mode self-cleanup; `prove_bite()`; both mode tails. No `SOLEUR_*` literal; the one `mktemp -d` lives in the helper under its owning trap. |
| `plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` (8 rows today; `passes`/`fails`, `pass()`/`fail()`, `set -euo pipefail`) | Rows 7–8 (Guard 2) with `-s` pre-checks and the strip-expression `grep -cF` pin; an independent `cases` counter, conservation check and `MIN_ROWS=10` floor — `boundary.test.sh`'s trailer block copied verbatim with `passes`/`fails` substituted and `MIN_ROWS` as the bound. Trailer `parity.test.sh: 10 passed, 0 failed (10 rows)` — the `($cases rows)` suffix is required by the copied block (precedent-diff). |
| `plugins/soleur/skills/ship/SKILL.md` (266 104 B; ceiling 274 000) | One bullet under `## Phase 5: Final Checklist` (the pre-PR checklist; `## Phase 6: Push and Create PR` follows it): the D4 command must print nothing (R24). ADR-229 ratchet has 7 896 B headroom; the bullet is < 300 B. |
| `scripts/guard-vacuity-floor.test.sh` | Add `plugins/soleur/skills/constraint-scaffold/test/bite-proof\.test\.sh` and `plugins/soleur/skills/constraint-scaffold/test/parity\.test\.sh` to `PROMOTED_FILES` (the regex on the `PROMOTED_FILES='^(…)$'` line). `plugins/soleur/skills/[^/]+/test/` is in `DEFERRED_DIRS` with a shrink-only `MAX_DEFERRED=47`; two new floor-bearing suites there would grow the ledger to 49 and red ARM 5c ("do NOT raise this number"). Promotion, not a raise, is the file's own documented remedy for every prior entrant (test-design). `plugins/soleur/test/debug-probe-residue.test.sh` is in `COVERED_DIRS` already. |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` | Regenerated with `bash plugins/soleur/test/fixture-relative-assert.test.sh --write-baseline` **only if** the suite reds, in the same commit as the operand edits, after `diff`-ing old vs new and confirming only rows for the edited files moved (else rebase first — R15). `fixture-dir-operand-assert.baseline.txt` likewise. |
| `CLAUDE.md` (repo root) | Append the one plain-prose pointer line (D9). |
| `plugins/soleur/NOTICE` › `mattpocock/skills` | `Used in:` gains `skills/reproduce-bug/SKILL.md, skills/test-fix-loop/SKILL.md, skills/constraint-scaffold/ (#8288)`; `Portions adopted:` gains one paragraph naming the four mechanics, the two deliberately not imported (the peer's four-rule deep-module scope; `hitl-loop.template.sh`), and that the emitted README is Soleur-authored and carries no credit per the constitution's vendored-content rule. |
| `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md` | D10 amendment section with consequences (a)–(f). |
| `knowledge-base/product/roadmap.md` | Only if Task 0.7 finds a line to tick; `wg-every-feature-listed-in-a-roadmap-phase` is satisfied by the issue's milestone either way. |

**Not edited, deliberately:** `plugins/soleur/agents/engineering/review/legacy-code-expert.md` (routing edge only); `references/depcruise-config.template`, `shared-runner.template`, the three workflow templates and the dogfood config/runner/workflows (every sentinel untouched); any `description:` frontmatter; `AGENTS.md` / `AGENTS.rules.md`; `.claude/workflow-transitions.json`; `apps/web-platform/server/git-lock-marker-telemetry.ts` (no new marker to mirror); `operator-digest/SKILL.md` (no new source).

**Diff-scope AC note.** The final tree will also carry the files the **pipeline** writes: `knowledge-base/INDEX.md` (regenerated), `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/{tasks.md,session-state.md,decision-challenges.md}`, this plan, learnings from compound. AC1's list names them so `/work` does not tick a false diff-scope criterion (#8207).

## Implementation Phases

### Phase 0 — Preconditions and measurements (no product code)

Every Bash call re-derives `MB="$(git merge-base origin/main HEAD)"` inline — the tool resets cwd per call and a pasted SHA goes stale (CTO).

- 0.1 `cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8288-reproduce-bug-red-loop && pwd && git merge-base origin/main HEAD`.
- 0.2 Re-fetch both peer files at the pinned SHA via `gh api 'repos/mattpocock/skills/contents/<path>?ref=c55ee46073ed923f86ce59a5eb3b6d895095d1b7' --jq .content | base64 -d` into the scratchpad; they are the source for the imported paragraphs and the corpus for AC2's shingle check.
- 0.3 `grep -n 'reproduce-bug\|test-fix-loop\|legacy-code-expert' plugins/soleur/lib/workflow-fidelity.ts plugins/soleur/test/workflow-fidelity.test.ts .claude/workflow-transitions.json` → zero.
- 0.4 `time (cd apps/web-platform && bash scripts/constraint-gates.sh)`; record seconds ×3 (+ one worktree pair) as the per-run cost in the PR body.
- 0.5 Re-run the one-hop measurement on a scratch fixture and copy the two `error <rule>: … <file>` lines verbatim into the suite's stub outputs (S-real-minus-direct-transitive, S-direct-only, S-lines-rc0, S-bare-tokens are derived from that real output).
- 0.6 Baselines before any edit: `bash plugins/soleur/test/fixture-relative-assert.test.sh` and `fixture-dir-operand-assert.test.sh` green; `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` exit 0; `bun test plugins/soleur/test/harness-parity-tree.test.ts` green; `bash scripts/guard-vacuity-floor.test.sh` green; `git ls-files -- . ':!knowledge-base' | wc -l` (Guard 4's floor operand); `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` prints `8 passed`; `wc -c plugins/soleur/skills/ship/SKILL.md` against `skill-body-budget.json`.
- 0.7 `grep -n 'peer\|mattpocock\|8288' knowledge-base/product/roadmap.md` — decide the roadmap edit.
- 0.8 Re-derive the next free ADR ordinal across all `origin/*` refs (expected 230).

### Phase 1 — RED: the suites before the guards

- 1.1 Write `test/bite-proof.test.sh`: fixture builder (with a `commit_instructions_files` option for harness row e); the stub-`depcruise` builder (`make_stub_depcruise <dir> <stdout-file> <rc> [<kill-pid-file>]`); toolchain locate-or-install block (verbatim shape from `boundary.test.sh`); toolchain-free cases (C2 precondition 65 on a fixture without `components/`; C3 pointer arms — `CLAUDE.md` present / only `AGENTS.md` / neither; C4 idempotency of README block and pointer; no-`@`; cleanup-list ↔ refuse-list pin; `trap`-before-`worktree add` shape pin; rule-name ↔ template `name:` pin); stub cases (S-direct-only → 72; S-lines-rc0 → 72; S-bare-tokens → 72; S-real-minus-direct-transitive → verdict, rc 0; S-preprobe-violation → 74 listing the file; S-fail72 in default mode → 72 **and** `git status --porcelain` empty afterwards; S-term (stub kills the scaffold during the pre-probe pass) → exit 143, `git worktree list` shows one worktree, no `mktemp` dir left); real cases (C1 default mode full run → rc 0, verdict line with `@direct`/`@via-hop`/`depcruise=`, README block and pointer present once, baseline present, `git worktree list` clean; C6 commit then `--refresh-baseline` → rc 0, verdict, README/pointer untouched; C8 populated tree; C-e committed instructions files → rc 0, appended once each). Independent `cases`, conservation, `TOOLCHAIN_FREE_MIN_ASSERTIONS`, `MIN_ASSERTIONS` (each `printf >&2; exit 1`, in the `[[ "$cases" -lt "$MIN" ]]` shape).
- 1.2 Write `plugins/soleur/test/debug-probe-residue.test.sh` (Guard 4) with `$ROOT` argument, two predicates, population floor.
- 1.3 Run both: every real and stub case RED against today's script (no `prove_bite`, no precondition, no README, no pointer); Guard 4 green on today's tree — its RED evidence is rows 1/2/6/8 on synthesized repos, recorded now.
- 1.4 `bash scripts/lint-orphan-test-suites.sh` → `0 orphaned`.

### Phase 2 — GREEN: `constraint-scaffold.sh`

- 2.1 Header, attribution, three-dirs precondition, `with_detached_worktree()`, `capture_baseline_mergebase()` refactored onto it (C1 covers the merge-base path end-to-end).
- 2.2 `append_once()`, `emit_readme()` (inline `sed -e '1{/^…Inspired by /d}' -e "s|__TARGET_DIR__|$TARGET_REL|g"` — opener elided in prose, see D8), `emit_pointer()` — called **after** `prove_bite()` in the default-mode tail.
- 2.3 `verdict_fail()` with default-mode self-cleanup and log tail; `prove_bite()` per D6; both mode tails.
- 2.4 Suite green; then execute Guard 1's 14 mutation rows (1–12, 3b, 3c) and seven harness rows (a–g), reverting each, recording each observation.

### Phase 3 — Templates, dogfood, parity

- 3.1 Write `references/boundary-readme.template` (D8 content; attribution comment on line 1; no peer sentence).
- 3.2 Place `apps/web-platform/server/README.md` = emitter transform of the template; append the pointer line to `CLAUDE.md` (plain prose, no `@`).
- 3.3 `parity.test.sh` rows 7–8 + ADR-193 floors; execute Guard 2's eight rows.
- 3.4 `bash scripts/markdown-lint.sh` clean on the new README; `bash .github/scripts/test/test-no-at-mention-credfile-footgun.sh` clean.

### Phase 4 — Prose: `reproduce-bug`, `test-fix-loop`, `constraint-scaffold`, `ship`

- 4.1 `reproduce-bug/SKILL.md` per D1–D5. Imported paragraphs from the Task 0.2 fetch; composition sentences in Soleur's voice; Phase 3 (Playwright) byte-preserved except the two lines in D1; `redact-a11y-snapshot.py` reference kept verbatim; attribution comment placed before the cloud-mode block.
- 4.2 `test-fix-loop/SKILL.md` per D2/D4/D5.
- 4.3 `constraint-scaffold/SKILL.md` per Files to Edit; `ship/SKILL.md` one bullet.
- 4.4 `bun test plugins/soleur/test/harness-parity-tree.test.ts` (ADR-226), `bun test plugins/soleur/test/components.test.ts`, `bun test plugins/soleur/test/devin-cloud-mode.test.ts` green; `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts test/plugin-root-anchoring.test.ts` green.
- 4.5 Execute Guard 3's five rows on a scratch branch and Guard 4's nine rows; record.

### Phase 5 — Repo-global ratchets (BEFORE the review panel — operator-mandated)

These are **existing CI gates run locally**, not gates this bundle introduces. Run each with **its own** input derivation; paste each trailer line into the PR body. `MB` is re-derived inline in every line.

- 5.1 `bash scripts/guard-vacuity-floor.test.sh` — after adding `bite-proof.test.sh` and `parity.test.sh` to `PROMOTED_FILES` (Files to Edit): the new floors enter the covered population, the deferred ledger stays at `MAX_DEFERRED`, and every new floor survives the neutered-helper mutants (its `[FATAL] … floor` line lands in `FIRES_LIST`).
- 5.2 `python3 scripts/lint-trap-tempfile-ownership.py --changed` exit 0 and `python3 scripts/lint-trap-tempfile-ownership.py --check-highwater` exit 0 (the helper's `mktemp -d` has an owning trap; the suites' `TMPROOT`s carry `EXIT INT TERM` traps).
- 5.3 `python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"` → clean (no `hr-*`/`wg-*` body touched).
- 5.4 `bash plugins/soleur/test/fixture-relative-assert.test.sh` — **if** it reds: regenerate with `--write-baseline`, `diff` the old and new baseline, confirm only rows for `constraint-scaffold.sh`, `bite-proof.test.sh`, `debug-probe-residue.test.sh`, `parity.test.sh` moved (otherwise `main` moved under you — rebase first), commit the baseline **in the same commit** as the operand edits with the per-file delta in the message, re-run → green. Same for `fixture-dir-operand-assert.test.sh`.
- 5.5 `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` → clean (`ship` stays under 274 000).
- 5.6 `bash scripts/lint-orphan-test-suites.sh`; `bash plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` (unchanged, still green).
- 5.7 **First in-target proof, pre-merge** (spec-flow): with `apps/web-platform/node_modules` installed and a clean tree, `bash plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh --refresh-baseline` prints the verdict line and exits 0; `git status --short` is empty afterwards; `git worktree list` is unchanged. Paste the verdict line into the PR body. The full battery is the `/ship` Phase 4 checkpoint, not a planning-phase step.

### Phase 6 — ADRs, NOTICE, docs, evidence

- 6.1 `soleur:architecture` → ADR-071 amendment and ADR-230 (D10); sweep the ordinal into this plan, `tasks.md` and the two SKILL.md citations if it moved.
- 6.2 `plugins/soleur/NOTICE` entry update; per `hr-third-party-content-grep-on-undertaking`, `git diff "$(git merge-base origin/main HEAD)" | grep -n 'Matt Pocock\|mattpocock'` must show only the attribution comments, the NOTICE lines and the ADR/plan references — none under `apps/web-platform/`; and the AC2 shingle check over the emitted README against both peer blobs prints `0`.
- 6.3 `bash scripts/sync-readme-counts.sh` leaves no diff (no component added).
- 6.4 Write `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/decision-challenges.md` with the entries in §Plan Review, for `ship` to render.
- 6.5 PR body: one line per guard (`Guard N: k/k RED, h/h harness as specified`), the ratchet trailers, the RED-run evidence from 1.3, the bite-proof cost from 0.4, the 5.7 verdict line, and the changelog line from §Plan Review for `soleur:feature-tweet` at ship.

## Acceptance Criteria

### Pre-merge (PR)

Each criterion names the command that decides it; where a gate is claimed green, the gate's own invocation runs. `MB` = `$(git merge-base origin/main HEAD)`, re-derived inline.

1. **Diff scope.** `git diff --name-only "$MB"` is a subset of: the five `Files to Create`, the eleven `Files to Edit`, `knowledge-base/INDEX.md`, this plan, `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/**`, `knowledge-base/project/learnings/**` (compound), and `plugins/soleur/test/fixture-dir-operand-assert.baseline.txt` if regenerated. **No new skill directory**, nothing named `wizard`, no `description:` change (`git diff "$MB" -- 'plugins/soleur/skills/*/SKILL.md' | grep -c '^[-+]description:'` → 0).
2. **Attribution present, verbatim, in the distribution; none in the emission; no peer sentence emitted.** For `reproduce-bug/SKILL.md` and `test-fix-loop/SKILL.md`: `grep -c -- '<!-- Inspired by mattpocock/skills/skills/engineering/diagnosing-bugs/SKILL.md (MIT, Copyright (c) 2026 Matt Pocock). -->'` → 1 each. For `constraint-scaffold/SKILL.md`, `constraint-scaffold.sh`, `boundary-readme.template`: the same grep with `skills/in-progress/setup-ts-deep-modules/SKILL.md` → 1 each. `grep -c 'Inspired by' apps/web-platform/server/README.md` → 0. An 8-word shingle comparison (`python3` one-liner over normalised lowercase word sequences) between `apps/web-platform/server/README.md` and each pinned peer blob → `0` shared shingles. `legacy-code-expert.md` is not in the diff.
3. **Observability-first preserved.** In `reproduce-bug/SKILL.md`, the line number of `## Phase 1: Log Investigation` is less than that of `## Phase 2: Build a feedback loop`, and `grep -c 'hr-no-dashboard-eyeball-pull-data-yourself'` on it is ≥ 1.
4. **The gate is falsifiable.** `grep -c 'Keep investigating until a good understanding' plugins/soleur/skills/reproduce-bug/SKILL.md` → 0; `grep -cE '^\s*- \[ \] \*\*(Red-capable|Deterministic|Fast|Agent-runnable)\*\*'` → 4; ten numbered rungs under the `### Ways to construct one` sub-heading (`awk '/^### Ways to construct one/{f=1;next} /^###? /{f=0} f' … | grep -cE '^[0-9]+\. \*\*'` → 10 — flag-based awk scoped to the sub-section); `grep -c 're-run soleur:reproduce-bug'` ≥ 1.
5. **Hypotheses before testing, with discriminators, as a founder decision, in one comment.** The Phase 5 section contains the `If <X> is the cause, then` form, a `Discriminator` column header, `proceed / re-rank / add a fact`, and `founder checkpoint not presented (headless)`; `grep -c 'a4f2' plugins/soleur/skills/reproduce-bug/SKILL.md` → 0; `grep -c 'gh issue comment' plugins/soleur/skills/reproduce-bug/SKILL.md` counts only occurrences at or after the `## Phase 8` heading (one comment per run).
6. **Marker classes distinguished; ADR is the single normative copy.** `reproduce-bug/SKILL.md` Phase 6 names both `[DEBUG-<hex4>]` and `SOLEUR_` and cites `ADR-230`; the two-class **table** appears in the ADR and in no SKILL.md (`grep -c '| Removable probe | Permanent marker |' plugins/soleur/skills/*/SKILL.md` → 0); `grep -cE 'echo "SOLEUR_DEBUG|printf .SOLEUR_DEBUG' plugins/soleur/skills/*/SKILL.md plugins/soleur/skills/*/scripts/*.sh` → 0; `cd apps/web-platform && ./node_modules/.bin/vitest run test/git-lock-marker-telemetry.test.ts` green.
7. **Cleanup gate is shape-keyed, case-insensitive, untracked-aware, and at three sites.** `reproduce-bug/SKILL.md`, `test-fix-loop/SKILL.md` and `ship/SKILL.md` each contain the exact D4 command (with `-niE --untracked`, no `-I`, exclusion `':!knowledge-base/**/*.md'`); in `test-fix-loop/SKILL.md` it appears **before** the `test-fix-loop: checkpoint iteration` commit line; `bash plugins/soleur/test/debug-probe-residue.test.sh` green with its population line ≥ 2 500 and its second predicate matching 0 files on the real tree; Guard 3's and Guard 4's rows observed as tabled.
8. **Playwright prose untouched but for two lines.** `diff <(awk '/^## Phase 2: Visual/{f=1;next} /^## Phase 3/{f=0} f' <(git show "$MB":plugins/soleur/skills/reproduce-bug/SKILL.md)) <(awk '/^## Phase 3: Visual/{f=1;next} /^## Phase 4/{f=0} f' plugins/soleur/skills/reproduce-bug/SKILL.md)` shows exactly one added **non-blank** line (the rung-4 sentence) and one changed line (no longer containing `inform user`); `grep -c 'redact-a11y-snapshot.py' plugins/soleur/skills/reproduce-bug/SKILL.md` is unchanged; `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-anchoring.test.ts` green; `bun test plugins/soleur/test/devin-cloud-mode.test.ts` green.
9. **Routing edges canonical; hand-off form explicit; label created before use, without `--force`; comment body redacted mechanically.** `grep -c 'soleur:engineering:review:legacy-code-expert'` ≥ 1 in each of `reproduce-bug/SKILL.md` and `test-fix-loop/SKILL.md`; `grep -c -- "soleur:test-fix-loop --cmd" plugins/soleur/skills/reproduce-bug/SKILL.md` ≥ 1; `grep -c -- '--cmd' plugins/soleur/skills/test-fix-loop/SKILL.md` ≥ 1; `grep -c 'gh label create "action-required"' plugins/soleur/skills/reproduce-bug/SKILL.md` ≥ 1 and `grep -c -- '--force' plugins/soleur/skills/reproduce-bug/SKILL.md` → 0; `grep -c 'redact-engine.py' plugins/soleur/skills/reproduce-bug/SKILL.md` ≥ 1; `bun test plugins/soleur/test/harness-parity-tree.test.ts` green.
10. **Bite-proof wired into both modes, through the shared helper, with no seams.** `grep -cE '^\s*prove_bite\s*(#|$)' plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` → 2; `grep -cE '^\s*with_detached_worktree ' ` → 2 (both callers); the header exit matrix lists 71, 72, 73, 74; `grep -c 'CONSTRAINT_SCAFFOLD_TEST_' plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` → 0.
11. **Both rules named on their own edges, call-form anchored, evidence on stdout.** The step-4 assertion matches `^\s*error no-client-to-server-secret: .*direct\.tsx` and `^\s*error no-client-to-server-secret-transitive: .*via-hop\.tsx` on the captured log; the verdict line carries `depcruise=`; `verdict_fail` prints to stdout before `die`; `bash plugins/soleur/skills/constraint-scaffold/test/bite-proof.test.sh` green with its trailer ≥ `MIN_ASSERTIONS`; `bash -n` on the script exits 0 (`shellcheck` is not installed on this host — measured in bundle 1).
12. **Every sentinel intact.** `git diff "$MB" -- plugins/soleur/skills/constraint-scaffold/references/depcruise-config.template plugins/soleur/skills/constraint-scaffold/references/shared-runner.template 'plugins/soleur/skills/constraint-scaffold/references/*workflow*.template' 'plugins/soleur/skills/constraint-scaffold/references/fix-constraints-stage-*.template' apps/web-platform/.dependency-cruiser.cjs apps/web-platform/scripts/constraint-gates.sh apps/web-platform/.github/workflows/` produces **no output**; `bash plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh` green.
13. **No `SOLEUR_*` literal added to a skill script.** `git diff "$MB" -- 'plugins/soleur/skills/*/scripts/*.sh' | grep -cE '^\+.*(echo "|printf .)SOLEUR_'` → 0.
14. **README + pointer parity, written last.** `bash plugins/soleur/skills/constraint-scaffold/test/parity.test.sh` prints `10 passed, 0 failed (10 rows)`; `grep -c -- '<!-- constraint-scaffold:pointer -->' CLAUDE.md` → 1 and `grep -c '@apps/' CLAUDE.md` → 0; `bash scripts/markdown-lint.sh` clean on `apps/web-platform/server/README.md`; in the script, the `emit_readme` call's line number is greater than the default-mode `prove_bite` call's.
15. **Ratchets, each by its own invocation** (Phase 5): `bash scripts/guard-vacuity-floor.test.sh` exit 0 with both new skill-test suites listed in its `PROMOTED_FILES` regex and its ledger count unchanged at `MAX_DEFERRED`; `python3 scripts/lint-trap-tempfile-ownership.py --changed` exit 0 and `--check-highwater` exit 0; `python3 scripts/lint-rule-bodies.py --check --base "$MB"` exit 0; `bash plugins/soleur/test/fixture-relative-assert.test.sh` exit 0 (with any regenerated baseline in the **same** commit as the operand edits and only the expected rows moved); `python3 scripts/lint-skill-body-budget.py --base "$MB"` exit 0; `bash scripts/lint-orphan-test-suites.sh` → `0 orphaned`; the 5.7 refresh-mode run's verdict line is in the PR body.
16. **Suite floors are direct and recognisable.** In `bite-proof.test.sh`, `debug-probe-residue.test.sh` and `parity.test.sh`: `grep -cE '^\s*(fail|bad) "(anti-vacuity|accounting|floor)'` → 0; `grep -cE "printf '.*\[FATAL\]"` ≥ 2 per file; each floor is written `[[ "$<counter>" -lt "$<MIN>" ]]` over a counter the file increments with `<counter>=$((<counter> + 1))`.
17. **NOTICE updated and the undertaking grep run.** `grep -c 'skills/reproduce-bug/SKILL.md' plugins/soleur/NOTICE` → 1; `git diff "$MB" | grep -n 'Matt Pocock\|mattpocock'` lists only attribution comments, NOTICE lines and ADR/plan references, none under `apps/web-platform/`.
18. **ADRs landed.** `grep -c '^## Amendment 2026-09-19 (#8288)' knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md` → 1 and its Consequences name items (a)–(f); `ls knowledge-base/engineering/architecture/decisions/ADR-230-*.md` → one file whose `## Decision` carries the two-class table; the ordinal was re-derived across every `origin/*` ref immediately before merge and the sweep grep (`grep -rn 'ADR-230' knowledge-base/project/{plans,specs}/` + the two SKILL.md files) agrees with the file name.
19. **C4 unaffected, mechanically.** `bash plugins/soleur/test/c4-count-parity.test.sh` exit 0; `git diff "$MB" -- knowledge-base/engineering/architecture/diagrams/` empty.
20. **Guard batteries executed.** All 14 + 7 (Guard 1), 8 + 2 (Guard 2), 7 (Guard 3), 10 + 2 (Guard 4) rows applied and observed as tabled; the PR body carries one line per guard.
21. **No sibling closed.** The PR body contains `Closes #8288` and does not contain `#8289`, `#8290` or `#8292` in a `Closes`/`Fixes`/`Resolves` clause.
22. **Deferrals filed at ship, not here.** The three deferrals in §Deferrals have a `deferred-scope-out`-labelled issue each with re-evaluation criteria; their numbers appear in the PR body's `Filed:` line.
23. **Decision challenges rendered.** `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/decision-challenges.md` exists with the entries in §Plan Review, and `ship` renders it into the PR body / an `action-required` issue.

### Post-merge

24. `soleur:postmerge` confirms the plugin CI battery is green on `main` (scripts shard includes `bite-proof.test.sh`, `debug-probe-residue.test.sh` and the 10-row `parity.test.sh`).

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO (advisory, structured, Phase 2.5). Medium complexity, low-medium risk; the risk lives in the scaffold script. Five rulings adopted: worktree bite; refresh-mode bite with corrected rationale; README append-once; plain-prose pointer (no `@` import); new ADR for the marker taxonomy plus a mechanical CI grep. Surfaces named and folded: `plugin-root-anchoring.test.ts` pin; the drift guard's `SENTINEL_RE` call-form scope; `lint-orphan-test-suites.sh`; `cq-skill-description-budget-headroom` does not fire. The CTO's second, devex-lens pass at plan-review (R13–R15, R37, R38) is folded into the body.

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — no UI surface in Files to Create/Edit (mechanical UI-surface scan against `ui-surface-terms.md`: zero matches); CPO consulted at Phase 2.5 and again on the named panel because the issue carries an explicit "Founder outcome (CPO gate)" and the frontmatter declares `single-user incident` (CPO sign-off at plan time).
**Agents invoked:** cpo, cmo (named panel)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO (Phase 2.5): two of four founder outcomes over-promised and rephrased; the hypothesis checkpoint is a decision with a default; headless runs record the checkpoint's absence; the seam-absence finding routes via the existing `action-required` label; attribution is not emitted into the founder's README. CPO (named panel, R28–R31): create the label before adding it, order the Phase 2 asks with the data-retrieval one last, reframe the D8 challenge as inapplicable-by-content conditioned on a shingle check, and soften the digest phrase. CMO (named panel): brand-voice fit confirmed for the Phase 8 line; "locked down" reads as security to a founder — replaced; credit-in-source / none-in-emission is consistent with how Soleur talks about third-party work; a changelog line and a tweet are worth routing to `soleur:feature-tweet` at ship (recorded in §Plan Review).

## Plan Review

Eight reviewers plus the advisor consult; findings consolidated in `## Plan Review Revisions (R1–R44)`. Mechanical findings were applied to the body. The following **Taste / User-Challenge** entries are persisted to `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/decision-challenges.md` by Task 6.4 (headless — no pause), for `ship` to render:

1. **User-Challenge (D8 attribution scope).** Operator direction: *"Every file taking peer prose carries the MIT attribution comment from the issue verbatim."* Plan reading: the emitted `server/README.md` is Soleur-authored and shares no sentence with the peer file (AC2 shingle check = 0), so the constraint does not reach it by content; the template in Soleur's distribution carries the comment; constitution line 192 is the default. If a peer sentence ever survives into the README the default flips to keep the comment. Revert cost: one `sed` expression, parity row 7, the dogfood file — one commit.
2. **Taste (D7, refresh-mode bite).** DHH: install-time only. CTO, issue text ("every scaffold run"): keep. Plan keeps it; cost measured in Task 0.4. Revert: drop one call and one test case.
3. **Taste, applied and recorded (founder-facing wording).** CPO + CMO: digest phrase → *"we cannot yet add an automatic test that keeps this bug from coming back"*; checkpoint → *"the 3–5 likeliest causes, ranked"*; Discriminator rendered as *"what else you'd see if this is it"*. Applied because two named reviewers converged and it changes no scope; the originals are in R31 for a one-line revert.
4. **Taste, resolved (Phase 2 "captured artifact" ask).** CPO flagged the ask as data retrieval. Kept — it is imported peer text, bounded to after the instrumentation route, and the one thing instrumentation cannot capture; ordered last with a default of not asking (R29).
5. **Taste (ship checklist bullet).** Architecture-strategist: `ship` is the real last chokepoint; the plan adds one bullet there, which is a file the issue did not name. Revert: delete one line.
6. **Declined User-Challenges (recorded for transparency).** DHH R40: drop Phase 4 minimise and the perf branch — declined; both are named in the issue body (B3, B2). Advisor: split Phase 5 ratchets into a follow-up PR — declined; they are existing gates run locally.

Changelog line for ship (CMO): *"reproduce-bug now ends with a red-capable repro command, ranked hypotheses with verdicts, and a seam verdict; constraint-scaffold proves its gate bites on install (pass → fail → pass) and emits a boundary README."* Tweet draft for `soleur:feature-tweet`: *"Your agent no longer says 'I understand the bug.' It hands you a command: red before the fix, green after. And when a bug can't be caught by a test, it says so and routes it — instead of guessing."*

## Test Scenarios

### Acceptance tests (`bite-proof.test.sh`)

Suite order (test-design): **source pins → stub-driven → locate-or-install → toolchain probe → real**, so an `npm install` failure in the scripts shard cannot `exit 2` before the toolchain-free segments have run. The fixture's `node_modules` symlink is untracked, so re-pointing it between cases never trips the clean-tree guard.

- **Source pins** (no fixture run): the cleanup-list ↔ refuse-list pin; the `trap '_wt_cleanup` -before-`worktree add --detach` order pin; the rule-name ↔ template `name:` pin; the `verdict_fail` stdout-before-`die` shape pin.
- **Stub-driven** (needs `node`, `git`, no depcruise — every shard): with the three-branch stub S-clean (`[]` / `{"modules":[]}` / checkmark, rc 0): C2 fixture without `components/` → 65, nothing emitted; C3 pointer arms — (a) `CLAUDE.md` present → appended there only, (b) only `AGENTS.md` → appended there, (c) neither → `AGENTS.md` created with exactly the line; C4 idempotency of README block and pointer (run twice, counts stay 1); no-`@`; C-symlink (`CLAUDE.md -> elsewhere`) → warning on stdout, nothing written through the link, rc 0; C-tmpdir (`TMPDIR` inside the fixture) → 69 before any worktree; C6 commit, then `--refresh-baseline` → rc 0, verdict line, README/pointer byte-identical before/after. With per-case stubs: S-direct-only → 72; S-lines-rc0 → 72; S-bare-tokens → 72; S-real-minus-direct-transitive → verdict line, rc 0; S-preprobe-violation (clean arm fails with a real `error <rule>: … other.tsx` line) → 74 naming `other.tsx`; S-fail72 default mode → 72, `git status --porcelain` empty, `scripts/` and `.github/workflows/` dirs gone; S-term → exit 143, stdout `interrupted; removed:` line, one worktree in `git worktree list`, `git status --porcelain` empty, no leftover `mktemp` dir.
- **Real toolchain** (after the locate-or-install block; SKIP cleanly with `boundary.test.sh`'s probe when depcruise cannot parse `.tsx`): C1 default mode → rc 0, verdict with `@direct`/`@via-hop`, `depcruise=` equal to the real `dependency-cruiser/package.json` version and matching `depcruise=[0-9]+\.` (never `0.0.0-stub`), README block once, pointer once, baseline present, `git worktree list` clean; C8 populated tree; C-e committed `CLAUDE.md` + `server/README.md` → rc 0, appended once each; **C-warn** — the fixture's committed `.dependency-cruiser.cjs` is the template with `no-client-to-server-secret-transitive` at `severity: "warn"` → the runner prints `warn no-client-to-server-secret-transitive: …`, rc 0 → 72 (the one real 72, and the proof that `^\s*error ` rejects a `warn` line); C-chmod (non-root only) `chmod a-w "$FX/.git"` → 69, no `mktemp` dir left.
- **Floors:** each segment's constant is **derived at commit time** from `grep -c 'cases=\$((cases + 1))'` over that segment and written into the comment beside it, exactly as `boundary.test.sh` derives `MIN_ASSERTIONS` (test-design: the earlier hand-summed 10/12/9 matched neither count of the listed outcomes). `TOOLCHAIN_FREE_MIN_ASSERTIONS` = pins + stub-driven; `MIN_ASSERTIONS` = that + real; conservation check first; both in the `[[ "$cases" -lt "$MIN" ]]` shape.

### Regression

- `boundary.test.sh`, `generator.test.sh`, `emit-fix-constraints.test.sh` unchanged and green.
- `harness-parity-tree.test.ts`, `components.test.ts`, `devin-cloud-mode.test.ts`, `git-lock-marker-telemetry.test.ts`, `plugin-root-anchoring.test.ts` green.

### Integration verification (`soleur:qa`)

- Run `soleur:reproduce-bug` against a closed, already-diagnosed issue in this repo in dry form (no comment posted): the agent stops at Phase 2 with a named command or with the "cannot build a loop" stop; the hypotheses table renders with the Discriminator column and the proceed / re-rank / add-a-fact framing, presented without a question tool; Phase 9's shape grep prints nothing; nothing is posted before Phase 8.
- The Phase 5.7 refresh-mode run on a clean checkout (already executed pre-merge; QA re-reads its verdict line from the PR body and re-runs it once).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A founder repo's `tsconfig` has no `@/*` alias → the probe import cannot resolve | The runner's alias self-check fails the **pre-probe** pass with its own `::error::` naming the tsconfig — 71 with that message and the log tail, never a mysterious 72; default mode removes what it emitted; the README names the requirement. |
| The `-transitive` rule stops firing on a direct edge after a depcruise upgrade | Irrelevant to the assertion: each rule is asserted on its own edge (one-hop probe); stub S-real-minus-direct-transitive pins that a semantics change on the direct edge is tolerated. |
| Depcruise changes its `error <rule>:` output shape | `boundary.test.sh` reads the same output on every CI run; both red together; the version in the verdict line makes it diagnosable. |
| Refactoring `capture_baseline_mergebase()` onto the shared helper regresses the merge-base path | C1 runs the full default mode including capture against a fixture with a real `origin/main`; C6 runs refresh. Both would red. |
| A same-branch leak newer than the baseline makes the bite unprovable | Exit 74 names the files and says the gate is live; nothing is removed in refresh mode, and default mode restores the tree. |
| A real tag typed in five characters escapes the shape grep | The mint emits four; Guard 3 row 4 covers case; a five-character tag is out of shape by construction and is documented as such. |
| Renumbered phases confuse an agent mid-session with a cached copy | Skill files are read at invocation; no state carries phase numbers across sessions. |
| `parity.test.sh`'s new floor reds on an unrelated template change | The floor is a lower bound (10); rows can only be added; a deleted row is exactly what it must catch. |
| The pointer line in Soleur's own `CLAUDE.md` is loaded every session | One plain-prose line (~170 B), never an `@` import; recorded in ADR-071's amendment as a precedent-setting choice. |
| Bite-proof adds seconds and a worktree pair to every scaffold and refresh run | Measured in Task 0.4 and stated in the PR body; D7 explains what it buys. |
| The worktree's `node_modules` symlink resolves through `$TARGET/node_modules` — absent on a fresh clone, or hoisted to the repo root in a workspace | Same precondition the baseline capture already dies on (68); the 68 message now names hoisting as a cause. |
| ADR-230 collides with a sibling PR's ordinal | Re-derived across all `origin/*` refs before merge; the sweep grep in AC18 catches a stale citation. |
| `--write-baseline` regenerates all 340 rows and carries unrelated deltas from a moved `main` | Task 5.4 diffs old vs new and rebases first if any non-expected row moved. |

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Sub-number the new phases (1.5, 2.5 …) | No live consumer references a number; sub-numbering makes the ladder harder to cite from the report. |
| Put the ladder in `reproduce-bug/references/` | A gate an agent may not read is not a gate; the ladder is 10 lines. |
| Bite in place in the founder's tree | Residue class, trap in the founder's tree, SIGKILL leaves a module that breaks `next build`; the worktree proves the same content with none of it. |
| Environment-variable test seams (with or without a master switch) | A fixture-owned stub `depcruise` reached through the `node_modules` symlink drives every arm with zero production surface. |
| Assert only the direct rule name | Both rules are the gate; asserting each on its own edge is what lets the bite notice a softened or mis-scoped transitive rule on the real target without coupling to reachability-on-direct semantics. |
| README refuse-if-exists | Refuse-if-exists protects executable artifacts; a doc conflict should not block adoption (CTO). |
| Write README/pointer before baseline capture | Dirties a tracked instructions file → 67 with executables already emitted (the P0). |
| Five-arm pointer precedence | v1 has one target one level deep; two arms at the repo root are all the tests prove. |
| Shared `readme-emit.sed` | Every existing parity row inlines its transform; a divergence row is the mechanism. |
| A CI-time bite in the generated workflow | Deferral 2 records it as the stronger long-term home, blocked on ADR-074's write-free slot. |
| Diff-scoped `[DEBUG-` gate | Weaker than tree-wide (misses a probe committed in an earlier checkpoint). |
| Import obra/addyosmani/melodic-software additions | A third upstream per idea; the routing stop is native. |
| Fold the marker taxonomy into ADR-071 | Wrong home (L1 import boundary); a third consumer would not find it (CTO). |
| Drop refresh-mode bite (DHH) | Issue text says every scaffold run; recorded as a taste disagreement. |

## Deferrals

1. **`generator.test.sh` has no ADR-193 floor** (green on 0/0). Out of this bundle's scope; file as `deferred-scope-out` at ship with re-evaluation "when the next generator exit code is added". Milestone `Post-MVP / Later`.
2. **CI-time bite in the generated `constraint-gates.yml`** (self-test on every PR) — the CTO's "stronger long-term home"; re-evaluate when ADR-074's Stage A gains a write-free self-test slot. Same label.
3. **A mirrored-not-paged `SOLEUR_CONSTRAINT_SCAFFOLD_HALT code=<n> mode=<default|refresh>` from `verdict_fail`** for the hosted-runner surface (`plugins/soleur/` is vendored into the production image, so the scaffold can run where no transcript is read by a human). Requires registering the literal in `MARKER_RE` and its drift-guard test — a deliberate scope expansion the operator's marker-population caution asks to weigh, so it is filed rather than folded. Same label; re-evaluate when the first hosted invocation of `soleur:constraint-scaffold` is observed.

No GitHub issue is created during planning (pipeline constraint); all three are filed by `soleur:ship`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 — it is filled above.
- README and pointer are the **last** writes of a default-mode run. Moving them earlier reintroduces the P0 (67 with executables on disk).
- Documentation of the probe convention writes `<hex4>`, never a concrete four-hex tag — the shape grep and Guard 4 depend on it. The issue's `a4f2` example is banned by AC5.
- The bite-proof's rule-name assertion anchors on `^\s*error <name>: ` **on the named probe file** — the runner's zero-reachability prose carries the bare transitive token, and its violation annotation is on stderr; the assertion runs on the captured `2>&1` log so neither can satisfy it.
- Exactly one trap owner: `with_detached_worktree` installs before `worktree add` and clears before returning; no other function installs `EXIT`.
- Regenerate `fixture-relative-assert.baseline.txt` only if the suite reds, in the **same commit** as the operand edits, after diffing old vs new; row equality means a *fall* reds exactly like a rise.
- Every `--base` in Phase 5 is re-derived inline as `$(git merge-base origin/main HEAD)`, never pasted, never `origin/main`.
- The suites' `cases=$((cases + 1))` sits at top level next to each verdict, never inside `$( … )`; floors are written in the `[[ "$cases" -lt "$MIN" ]]` shape the meta-guard derives.
- The pointer line is plain prose with a repo-relative path — an `@path` line in `CLAUDE.md` is a Claude Code import and would load the README into every session.
- The attribution comment is verbatim from the issue, including the trailing period inside the comment; in the SKILL.md files it sits strictly between the frontmatter close and the `soleur-cloud-mode:start` line, which `devin-cloud-mode.test.ts` pins byte-identical.
- ADR-230 is provisional until merge; a renumber sweeps the plan, `tasks.md`, the ADR and both SKILL.md citations in one edit.
- `test-fix-loop` hand-off uses `--cmd '…'`; a bare command containing digits would be parsed as an iteration count.

## Plan Review Revisions (R1–R44)

Panel: DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO (devex), CPO, CMO; plus the Step 4.5 advisor consult. **Mechanical** rows were applied to the body; **Taste / User-Challenge** rows are surfaced in §Plan Review and `decision-challenges.md`.

| # | Source | Class | Revision |
|---|---|---|---|
| R1 | Kieran P0, architecture P0, spec-flow P0 | mechanical | README/pointer emits moved **after** `prove_bite()`; a fixture with committed `CLAUDE.md` + `server/README.md` added (Guard 1 harness e). |
| R2 | architecture P1, spec-flow P1 | mechanical | Default-mode bite failure removes every artifact the run emitted and says so; refresh mode says the baseline was rewritten. |
| R3 | architecture P1, spec-flow P2, Kieran P2 | mechanical | Exit 74 for real HEAD violations newer than the baseline, listing them; 71 stays for config/toolchain. |
| R4 | Kieran P1, spec-flow P1 | mechanical | `app/`-only arm, its case and Guard 1 row 8 cut; three-dirs precondition (65) added; README names it. |
| R5 | Kieran P1 ×2 | mechanical | Rows 7 and 9 re-homed onto stubs S-lines-rc0 and S-bare-tokens; assertions run on the captured `2>&1` log with the call-form anchored on the named file. |
| R6 | Kieran P1 | mechanical | `parity.test.sh` has 8 rows today; new rows are 7–8, floor 10, trailer `10 passed`. |
| R7 | Kieran P1 | mechanical | AC3 pre-edit count is 1 → `≥ 1`. |
| R8 | Kieran P2, architecture | mechanical | INT/TERM handler exits 143; row 5 becomes a source-shape pin plus the stub-delivered TERM case. |
| R9 | DHH P2, code-simplicity, CTO | mechanical | `readme-emit.sed` cut; inline expression on both sides; parity row pins it by `grep -cF`. |
| R10 | Kieran P2 ×2 | mechanical | AC4 rung count scoped to `### Ways to construct one`; AC8 "one added non-blank line". |
| R11 | DHH P0, code-simplicity, CTO | mechanical | All `CONSTRAINT_SCAFFOLD_TEST_*` seams and the master switch removed; fixture-owned stub `depcruise` drives every failure arm; no exit-64 reuse. |
| R12 | Kieran P2 | mechanical | Rule (c) claim reworded — trap ordering is ADR-129's requirement, not the lint's. |
| R13 | CTO high ×2 | mechanical | `verdict_fail()` prints on stdout and tails the captured log before `die`. |
| R14 | CTO, CPO a3, spec-flow P2 | mechanical | Phase 5 checkpoint presented in-turn without a question tool; one issue comment per run, at Phase 8. |
| R15 | CTO high ×2 + P2 ×2 | mechanical | 5.4 diffs old vs regenerated baseline; AC15 `--check-highwater` exit 0 not `== 79`; "if it reds, regenerate"; `MB` re-derived inline everywhere. |
| R16 | CTO | mechanical | Guard 4 grep `-I`; repo-root parameter so RED rows run on synthesized repos. |
| R17 | spec-flow P0 | mechanical | Hand-off to `test-fix-loop` happens after Phase 9 with the loop script committed by the agent. |
| R18 | spec-flow P1 | mechanical | `--cmd` / `--max` argument form in `test-fix-loop` Phase 0 and in the hand-off. |
| R19 | spec-flow P1, architecture P2, Kieran P2, code-simplicity, DHH | mechanical | Untracked-file `note:` and its case cut. |
| R20 | spec-flow P2 | mechanical | README says what the founder sees on a trip (red check + ADR-074 draft PR). |
| R21 | spec-flow P2 | mechanical | Refresh-mode dogfood run moved pre-merge as Task 5.7. |
| R22 | architecture P1 | mechanical | Guard 4 second predicate `SOLEUR_[A-Z_]*DEBUG`; failure-mode text names the drift guard's real coverage. |
| R23 | architecture P1, CPO | mechanical | ADR-071 amendment consequences (a)–(f) and the opt-out-flag rejected alternative. |
| R24 | architecture P2 | taste (applied, surfaced) | D4 command runs before every `test-fix-loop` checkpoint and in `ship`'s pre-PR checklist. |
| R25 | DHH P1, architecture P2, CTO | mechanical | Two-class table lives in ADR-230 only; skills carry spelling / mint / rule / cleanup / citation. |
| R26 | architecture P2 | mechanical | `append_once` trailing-newline guard. |
| R27 | architecture P2 | mechanical | Attribution comment strictly between frontmatter and the cloud-mode block (`devin-cloud-mode.test.ts` pin). |
| R28 | CPO a1, architecture P1, spec-flow P1, Kieran P1 | mechanical | `gh label create action-required … --force` before `--add-label`; P4/D5 claim scoped to where the digest runs. |
| R29 | CPO a2, spec-flow P1 | taste (resolved) | Phase 2 asks reordered — instrumentation first and default, environment access, captured artifact last and bounded; headless takes the first arm. |
| R30 | CPO b1, CMO | user-challenge (reframed) | D8 challenge reframed as inapplicable-by-content, conditioned on the AC2 shingle check; revert cost named. |
| R31 | CPO d, CMO 1/5 | taste (applied, recorded) | Digest phrase, checkpoint opener, Discriminator render reworded. Originals: "this part of your product cannot yet be locked down"; "Here are the 3–5 things I think could be causing it"; "Discriminator". |
| R32 | DHH P1, code-simplicity | mechanical | Pointer precedence → two arms at repo root; multi-level deferral deleted. |
| R33 | DHH P1 | mechanical | `with_detached_worktree` shared by baseline capture and bite. |
| R34 | DHH P1, CTO | mechanical | Real-runner variants C5/C5b/C5d replaced by stub cases; one real full run (C1) + populated-tree and committed-files fixtures remain. |
| R35 | DHH P1 | mechanical (partial) | AC source-text greps trimmed to regression pins and behavioural gates; the literal worktree-line grep dropped. |
| R36 | DHH P2 vs code-simplicity/CPO | taste (kept) | `parity.test.sh` floor retrofit kept, minimal, with `-s` pre-checks (CTO 15) — the suite gains rows this PR. |
| R37 | CTO | mechanical | Phase 2 ordered decision-first (checkboxes, gate, stop), ladder second. |
| R38 | CTO | mechanical | Mint via pure bash `printf '%04x'`. |
| R39 | DHH P1 vs CTO + issue text | taste (surfaced) | Refresh-mode bite kept. |
| R40 | DHH P1 | user-challenge (declined) | Phase 4 minimise and the perf branch stay — both are in the issue body. |
| R41 | code-simplicity | mechanical | Guard 4 floor derived from the measured population (5 168 → 2 500); floors written in the meta-guard's recognised shape; assertion counts re-derived with the constants. |
| R42 | code-simplicity | mechanical | Worktree copy ordering dependency stated inline; hoisted `node_modules` named in the 68 message. |
| R43 | CMO 2 | mechanical | AC2 shingle check ensures no peer sentence in the emitted README. |
| R44 | CMO 3 | taste (recorded) | Changelog line and tweet draft recorded for `soleur:feature-tweet` at ship. |

## Precedent Diff (deepen-plan Phase 4.4)

Eight pattern-bound behaviours were checked against the repo's canonical form before implementation. Verdicts:

| Pattern | Precedent | Verdict |
|---|---|---|
| `with_detached_worktree` (mktemp + traps before the destructive step + callback + cleanup) | `constraint-scaffold.sh` › `capture_baseline_mergebase()` (EXIT-only trap already precedes `worktree add`); signal arm from `scripts/rotate-sentry-actions-ro-token.sh` › `trap 'cleanup; trap - EXIT; exit 143' TERM HUP`; callback shape from `plugins/soleur/scripts/lib/session-state.sh` › `with_lock` (`"$@" \|\| rc=$?`) | Plan shape is fine with three precedent edits, all folded into D6: clear `EXIT` inside the signal arm; keep `WT="$(mktemp -d)"` on one line for the tempfile lint's regex; note the 130/143 split the repo uses elsewhere and why 143 alone is used here. |
| `append_once` marker-keyed append with newline guard | **No precedent, novel.** The repo's upserts are tempfile+`mv` (`operator-script.sh` › `soleur_op_env_upsert`); the only idempotent-append idiom is `grep -q key f \|\| echo … >> f`; the only trailing-newline test is `[ -z "$(tail -c 1 …)" ]` in `git-data-cutover-access.test.sh` | Shape prescribed literally in D8 (with the symlink refusal added by security review). |
| `verdict_fail` (verdict on stdout, then `die` to stderr) | `provision-doppler.sh` › the "Stdout, not stderr, because agent runtimes surface stdout and swallow stderr" comment; constitution › Code Style; the only other `verdict_fail()` (`scripts/followthroughs/inngest-cutover-flip-rollout-7761.sh`) is stderr-only and workflow-context — not a shape to copy | Plan shape is fine. |
| Stub binary at the process boundary | `plugins/soleur/skills/review/SKILL.md` ("stub only the binary … recording its argv"); `plugins/soleur/skills/work/SKILL.md` ("make the fake `exit 64` on a missing required flag"); canonical stub shape `plugins/soleur/test/issue-flow-measure.test.sh` (fake `gh` with argv log + `case`); `boundary.test.sh`'s symlinked toolchain | Plan shape is fine and is the *better* seam (the runner resolves depcruise by path through the symlink the SUT itself creates, so a PATH shim would never be reached); argv log + `exit 64` adopted in D6. |
| `--cmd` / `--max` in a `$ARGUMENTS` contract | `plugins/soleur/skills/schedule/SKILL.md` ("If `$ARGUMENTS` contains `--name`, `--skill` … extract values directly … Optional flags: `--timeout` (minutes, default 30)") — the only value-carrying-flag precedent | Adopt that phrasing; say "iterations" so `--max` never reads as `schedule`'s `--max-turns`. |
| ADR-193 floor retrofit into an accumulate-then-exit suite | `boundary.test.sh` trailer block (the `[FATAL] accounting` literal is load-bearing — the meta-guard's ARM 10 greps it) | Adopt verbatim with `passes`/`fails` substituted for `parity.test.sh`; both new suites copy it byte-for-byte with their own basename and `($cases assertions\|rows)` suffix. |
| Shingle / near-duplicate check | `plugins/soleur/test/agent-originality.test.ts` › `SHINGLE_N = 8`, `neutralize()`, `shingles()`, `jaccard()` | Adopt the normalisation (lowercase, `[^a-z0-9\s]+` → space, n = 8); AC2 reports an intersection **count**, stated as such. |
| `gh label create` before `--add-label` | `.github/workflows/scheduled-terraform-drift.yml` › `gh label create "action-required" --description "Needs a human action" --color "B60205" 2>/dev/null \|\| true`; `ship/SKILL.md` › the `follow-through` twin | Adopt verbatim; **drop `--force`** (appears in no shipped skill; rewrites an existing label's colour/description). |

Scheduled work: none introduced (no cron, no Inngest function, no workflow).

## Deepen-Plan Reconciliation (R45–R72)

Eight deepen agents (stub prototype, verify-the-negative, precedent-diff, git-history, test-design, security, observability, prompt-engineer). Verify-the-negative confirmed 15/15 claims; git-history confirmed 12/12 attribution claims (ADR-230 free across all `origin/*` refs; only this branch's own PR touches the three skills). Every row below is **mechanical** and applied to the body unless marked.

| # | Source | Revision |
|---|---|---|
| R45 | stub-prototype (measured) | Stub `depcruise` must branch on `--output-type` (`baseline` → `[]`, `json` → `{"modules":[]}`, `err` → clean or probe arm by cwd existence test); a single canned output/rc could never reach 72 (dies 68 at capture or 71 at the pre-probe pass). D6 carries the branching table and the smallest working stub; `make_stub_depcruise` gains clean/probe arms; runner calls written `\|\| rc=$?`. |
| R46 | stub-prototype (measured) | TERM delivered inside a foreground capture fires the handler after the runner returns and before the next statement; `exit 143` from the handler runs the EXIT trap — S-term's assertions are satisfiable as tabled. Kept. |
| R47 | security P1 | D4 command gains `--untracked`; Guard 3 row 6 (probe in an untracked file). |
| R48 | security P1 | `-I` removed from D4 and Guard 4; exclusion narrowed to `':!knowledge-base/**/*.md'` (nine executables tracked under `knowledge-base/`); Guard 3 row 7 (NUL-byte file). |
| R49 | observability P1, test-design P0 (measured) | Guard 4's `SOLEUR_[A-Z_]*DEBUG` predicate is red today on `permission-log.ts`; narrowed to the emit call-form; `permission-log.ts` and a synthesized env-read pinned as must-PASS rows 7 and 10. |
| R50 | test-design P1 | `scripts/guard-vacuity-floor.test.sh` `PROMOTED_FILES` gains `bite-proof.test.sh` and `parity.test.sh` (otherwise the deferred ledger grows 47 → 49 and ARM 5c reds); added to Files to Edit and Task 5.1. `debug-probe-residue.test.sh` gets a three-row `cases` counter + conservation + `MIN_CASES=3` so the meta-guard classifies it and AC16 holds. |
| R51 | observability P1 | Default-mode INT/TERM handler removes the six emitted artifacts and prints `interrupted; removed: <list>`; S-term asserts `git status --porcelain` empty. |
| R52 | security P1 | `append_once` refuses a symlinked target (`[[ -L ]]`) before reading or writing; refusal is a stdout warning after a successful bite; harness row (g). |
| R53 | security P2 | `TMPDIR` resolving inside the repo is refused (69) before any worktree is created; harness row (g). |
| R54 | security P2 | `verdict_fail` `rmdir`s the two `mkdir -p` dirs; recovery text names `git worktree prune`. |
| R55 | security P2 | A failure inside `emit_readme`/`emit_pointer` after a successful bite is a stdout warning, not a fatal (prose is not the gate). |
| R56 | security P1 | Phase 8 comment body and the `--cmd` string pass through `plugins/soleur/skills/incident/scripts/redact-engine.py` (exit 1 = redaction needed) before posting; AC9 greps for it. |
| R57 | security P1 | A fixture derived from a captured trace is synthesized or redacted before commit; Phase 9 checkbox "no production payload in the committed loop script or fixture". |
| R58 | security P2 | Probe payload rule in D3 / ADR-230 (discriminators only; removed before any push). |
| R59 | precedent (a) | Signal arm `'_wt_cleanup; trap - EXIT; exit 143'`; same-line `mktemp -d`; 130/143 note. |
| R60 | precedent (b) | `append_once` prescribed literally (no precedent). |
| R61 | precedent (d) | Stub logs argv to `calls.log`; `exit 64` on unrecognised argv; version `0.0.0-stub`. |
| R62 | precedent (e) | `test-fix-loop` Phase 0 uses `schedule/SKILL.md`'s `--flag value` phrasing; "iterations" not "turns". |
| R63 | precedent (f) | `boundary.test.sh` trailer block copied verbatim into all three suites; `parity.test.sh` trailer gains `(10 rows)`; AC14 updated. |
| R64 | precedent (g) | AC2 shingle check uses `agent-originality.test.ts`'s normalisation; intersection count. |
| R65 | precedent (h), security P2 | Label creation per `scheduled-terraform-drift.yml`; `--force` dropped; AC9 asserts its absence. |
| R66 | verify-the-negative | `ship`'s pre-PR checklist is `## Phase 5: Final Checklist` (before `## Phase 6: Push and Create PR`); named in Files to Edit. |
| R67 | observability P1 | Hosted-runner surface (plugin vendored into the prod image) acknowledged; a mirrored-not-paged `SOLEUR_CONSTRAINT_SCAFFOLD_HALT` is **Deferral 3**, not folded — AC13 and the operator's marker-population caution stand. Layer-7 durable-artifact deviation for default-mode 71–74 verdicts recorded in §Observability. |
| R68 | test-design P2 | Real case C-warn (`severity: "warn"` copy → 72) added; Guard 1 row 7 gains its real twin. |
| R69 | test-design P3 | Guard 1 is 14 rows; floor constants derived at commit time from `grep -c 'cases=\$((cases + 1))'` per segment; suite ordered source-pins → stub → install → probe → real; C1 asserts the real depcruise version (harness row f); C6 lives in the stub-driven segment only. |
| R70 | test-design P2 | Row 5's shape pin matches `trap '_wt_cleanup` specifically; behavioural twin C-chmod (non-root) added. |
| R71 | test-design P1 | Guard 4 runs predicates first and prints findings before any floor; `MIN_POPULATION` is a parameter so synthesized RED rows red for the right reason; population read from the repo toplevel. |
| R72 | observability P1/P2 | `discoverability_test.command` now names `bite-proof.test.sh`; every `alert_route` carries a layer substring (`cli-stdout-artifact` / `workflow run log`); the drift-guard coverage description corrected (SKILL.md half is `DOMAIN_RE`-filtered; `apps/**` and `plugins/soleur/test/**` unscanned); "environment access" defined as non-shell (`hr-no-ssh-fallback-in-runbooks`); the 65 precondition message goes through the stdout path. |

**Prompt-engineer output.** Paste-ready prose for all six edit sites is saved at `knowledge-base/project/specs/feat-one-shot-8288-reproduce-bug-red-loop/prose-drafts.md`, with the R47/R65 corrections applied. Seven peer-vs-Soleur conflicts are resolved there as composition rather than import; two are worth naming for NOTICE accuracy: rung 10 (`soleur:agent-browser`) is **not** peer prose and must not be listed as adopted verbatim, and the peer's "If the redacted output is not enough … ask the user" sentence is dropped in favour of the ladder (data-retrieval ask). The peer's "Spend disproportionate effort here. Be aggressive. Be creative. Refuse to give up." line is kept for fidelity (~90 B) despite the vague-qualifier rule — it is the peer's emphasis, and the four checkboxes carry the measurable form.
