---
title: "feat(ship): wizard-generated operator bootstrap scripts + Merge Danger block"
date: 2026-09-18
slug: feat-ship-operator-bootstrap-wizard-merge-danger
branch: feat-one-shot-8287-operator-bootstrap
issue: 8287
closes: 8287
type: feature
lane: cross-domain
domain: engineering
priority: p1-high
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

No `spec.md` existed for this branch when planning began, so `lane:` could not be carried forward
and is set to `cross-domain` (TR2 fail-closed). That value is also the honest one: Engineering,
Product and Operations were all assessed relevant and all three returned findings.

## Overview

Bundle 1 of 5 from the mattpocock/skills peer-plugin audit. Four scoped changes turn
Soleur's operator-step machinery from an accounting system into a delivery system:
a generator skill plus a shared bash library that produces the `bootstrap.sh` artifact
two existing hard rules already mandate; an undo-first reversibility verdict
in the PR body `ship` generates; a capability map so a founder facing
98 skills can find the right one; and a short re-pitch skill for a message that did
not land. Peer skill names are replaced with names that follow the shipped
`<noun|domain>-<verb>` prefix-grouping convention, and each new skill is wired into
routing, discoverability, a named predecessor, the lifecycle registry, and the
docs-count manifest.

## READ THIS FIRST — the revisions block supersedes the body

A seven-agent plan review (DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, cpo, cto-devex) produced **`## Plan Review Revisions (R1–R40)` at the END of this
file**. Those revisions **cut or reverse a substantial part of what the sections below describe**, and
the body was deliberately left intact so the reasoning that produced each reversal stays auditable.

**`/work` must read the revisions block before implementing anything below it.** Where the two
conflict, the revisions win. The body is the record of how the plan got here; the revisions are the
plan.

The mechanisms the body still describes at length but which the revisions **cut**:

| Body describes | Superseded by | Status |
|---|---|---|
| The inlined library and its `STAGES` marker invariant (~11 mentions) | **R6** | **Cut** — the generated script now `source`s the library |
| Guard 2 / regeneration parity / `regeneration-parity.test.sh` (~10 / ~6 mentions) | **R6** | **Cut** with the inlined mode |
| Guard 1, `enums/go-routes.json`, `parse-label.test.sh`, `tasks/go-routing.jsonl` (~8 / ~5 mentions) | **R9** | **Cut** — the `drain-prs` drift is filed as its own issue |
| Guard 5 (~12 mentions) | **R10** | **Cut** — the property is bought twice already |
| `provision-{cloudflare,doppler,github}` characterization suites + fixtures | **R11** | **Cut** — they ship with their refactors |
| The `provision-github.sh` dry-run hoist (~2 mentions) | **R12** | **Cut** — it changes the output it would golden |
| `verify-bootstrap-run.sh --self-test` (~3 mentions) | **R13** | **Cut** — `--ledger --last` survives |
| `predecessor-wiring.test.sh` as a file (~4 mentions) | **R14** | **Cut** — folded into `components.test.ts` |
| A new AGENTS Communication rule + index pointer | **R15** | **Cut** — `cm-when-proposing-to-clear-context-or` is amended instead |
| The `**Door:**` field (~10 mentions) and the Phase 5.5 merge hold | **R7** | **Cut** / **deferred** |
| The `none produced` sentinel | **R7** | **Collapsed** into `none known` |
| The secret registry and output-scrub trap | **R5** | **Cut** |
| D12's Test-24 rationale | **R25** | **Falsified** — the conclusion survives on Guard 5's prologue reason |
| D2's two-carve-out set | **R8** | **Replaced** by a three-class set; the ack class takes **no** skip variable |
| ADR-226 "extends" ADR-178 | **R24** | **Relabelled** "constrained by" |

Guards drop 5 → 3 (Guards 3 and 4 survive, plus one byte-equality assertion). Files to create
18 → 12; files to edit 19 → 14. No property in P1–P5 is lost.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Check run | Verdict |
|---|---|---|
| #8287 is open and unresolved | `gh issue view 8287 --json state,closedByPullRequestsReferences` → `OPEN`, `[]` | **Holds** |
| Peer repo is MIT | `head -5 <clone>/LICENSE` → `MIT License / Copyright (c) 2026 Matt Pocock` | **Holds** |
| `auto_command:` has no implementing template under `plugins/soleur/` | `grep -rn "auto_command" plugins/soleur/` → zero hits | **Holds** |
| `bootstrap.sh` has no implementing template under `plugins/soleur/` | `grep -rn "bootstrap.sh" plugins/soleur/` returns hits, but every one is a *reference* to an infra script (`inngest-bootstrap.sh`, `soleur-host-bootstrap.sh`, `git-data-bootstrap.sh`) — no generator, no template | **Holds, with a correction:** the grep is not zero; the *template* is absent |
| Four `provision-*` scripts total 1041 lines | `wc -l plugins/soleur/skills/provision-*/scripts/*.sh` → 241+345+300+155 = 1041 | **Holds** |
| 99 shipped skills | `ls plugins/soleur/skills/ \| wc -l` → 99 dirs, but `find … -name SKILL.md` → **98**; `plugins/soleur/skills/flag-bootstrap/` has no `SKILL.md` | **Correction:** 98 skills, 99 directories |
| `skill-creator/references/skill-structure.md:158` documents verb-noun | Read `:157-170` — the `<naming_conventions>` block says "Use **verb-noun convention**" | **Holds** |
| The verb-noun defect "is tracked separately in the bundle-4 issue" | `gh issue view 8290` — its scope is the invocation axis, `AGENTS.rules.md` negation phrasing, and four `skill-creator/references/` authoring levers. It **does not name** the verb-noun naming convention | **STALE.** See Decision D7 |

### Property List (Phase 0.6b)

| # | Property (observable outcome) |
|---|---|
| P1 | A founder facing ≥2 post-merge steps blocked on one credential runs a script, not a prose checklist. |
| P2 | Every Soleur-generated operator script behaves identically: same progress counter, same confirm gate, same secret handling, same closing summary. |
| P3 | A founder reading a generated PR body can tell, before approving, whether the merge can be undone and how far its effects reach. |
| P4 | A founder facing 98 skills can find the one that fits their situation, and knows what to do at a context boundary. |
| P5 | A founder who did not understand the agent's last message can get it re-pitched in plain language in the moment, not a week later in the digest. |

### Cut List (Phase 0.6b)

| Mechanism the ask proposed | Property | What already covers it | Disposition |
|---|---|---|---|
| Port the peer `template.sh` library verbatim (204 L) | P2 | Five of six primitives already exist in-repo: stage progress + preflight + closing summary at `apps/cla-evidence/infra/bootstrap.sh:57-61,76-88,98-103,110,307-315`; `.env` upsert **duplicated 4×** across `plugins/soleur/skills/community/scripts/{linkedin,x,bsky,discord}-setup.sh`; `gh secret` via stdin at `plugins/soleur/skills/operator-digest/scripts/provision-operator-digest-repo.sh:70-96`; hidden entry + xtrace-refusal at `provision-doppler/scripts/provision-doppler.sh:14-20` and `provision-hetzner/scripts/provision-hetzner.sh:123` | **CUT the port. EXTRACT instead.** Only cross-platform URL opening (macOS `open` / WSL `wslview`) is genuinely new — in-repo prior art is `xdg-open`-only at `community/scripts/linkedin-setup.sh:327-329`. Porting would create a *sixth* copy of the `.env` upsert. |
| Invent a sourced-shell-library convention | P2 | `apps/cla-evidence/scripts/_cf-admin-token.sh:1-14` already establishes it: `_*.sh`, `# shellcheck shell=bash`, sourced-never-executed, documented sourcing preconditions, named call sites, companion `_cf-admin-token.test.sh` | **CUT.** Mirror the existing convention. |
| A second capability map in `go.md` | P4 | `plugins/soleur/commands/help.md:45-82` is already a harness-aware capability map with manifest-derived counts | **CUT the second map. EXTEND the existing one**, and point `go.md` at it. |
| Restate the five phase-boundary options from scratch | P4 | Three of five are already specified as AGENTS rules: *`/clear`* by `cm-when-proposing-to-clear-context-or`, *handoff* by `wg-end-of-work-emit-resume-prompt`, *subagent* by `cm-delegate-verbose-exploration-3-file` | **CUT the restatement.** The genuinely new content is the **ordering** (first yes wins), **Continue ruled out first**, and **`/compact` placed last**; the other three cite their existing id. **Correction:** an earlier draft of this row cited `go.md:183` as covering *Continue*. Verified at `go.md:181-185` — that block is the **lifecycle handoff chain** (`plan → work → review → qa → compound → ship`), a different axis entirely. The issue conflates pipeline handoff with context-boundary handoff; this plan does not. |
| Author an ASD-STE100 rule set inside `operator-explain` | P5 | Registry saturated (`simple-english` 3423★, `asd-ste100` 497★, `ste100` 234★); the plain-language **register** is already written at `plugins/soleur/skills/operator-digest/SKILL.md:22-28` | **CUT.** Cite ASD-STE100 by name; point at operator-digest's Register as the single source. |
| Cite `plugins/soleur/docs/pages/glossary.njk` as the skill's vocabulary | P5 | It is a **marketing** glossary (~8 terms: Company-as-a-Service, agentic engineering, MCP, plugin, skill) in Eleventy HTML — not a controlled vocabulary | **CUT.** Category mismatch. Vocabulary source deferred to `kb-glossary` (#8289, bundle 3); until then the skill reads the repo's own `CLAUDE.md`/`AGENTS.md` terms. |

Nothing in the Cut List removes a *property* — every cut replaces a new mechanism with one already on `origin/main`.

### Value-Proposition Measurement (Phase 0.6c)

The saving claimed is **de-duplication, measured**: the `.env`-upsert block exists 4× under `plugins/soleur/skills/community/scripts/` (`linkedin-setup.sh:426-465`, `x-setup.sh:370`, `bsky-setup.sh:200`, `discord-setup.sh:209`), and the confirm/secret-prompt idiom is re-rolled across 1041 lines of `provision-*.sh`. Commands that produced the numbers: `grep -ln "chmod 600" plugins/soleur/skills/community/scripts/*.sh` (4 files) and `wc -l plugins/soleur/skills/provision-*/scripts/*.sh` (1041). No performance or API-cost saving is claimed.

### Measured budgets (Phase 1.8)

- **Skill description budget: 2442 / 2442 words — ZERO headroom.** `SKILL_DESCRIPTION_WORD_BUDGET` is defined at `plugins/soleur/test/components.test.ts:21`; the assertion is at `:163`. Measured by replicating the test's own computation (the `description` frontmatter of every `plugins/soleur/skills/*/SKILL.md`, `split(/\s+/).filter(Boolean).length`, summed) over the 98 skills that have a `SKILL.md`. This bundle adds **two** descriptions, so the constant must move or two siblings must be trimmed. Every prior skill addition recorded in that constant's own comment took the bump path against a documented zero-headroom baseline — this plan follows that precedent (Decision D6).
- **AGENTS always-loaded byte budget: `[OK] B_ALWAYS=42640`** against the 46000 cap (`python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md`). **3360 bytes headroom.** This plan amends two existing rule bodies and adds no new rule id, so no new index pointer is created and `cq-rule-ids-are-immutable` is satisfied.

### Registration surfaces a new skill must reach

Derived from the `cron-list`/`cron-delete`/`flag-list`/`flag-delete` adding commit `f4de63f16d3bde8ba22c3727950fa95ace6d7524`, plus direct reads:

1. `plugins/soleur/skills/<name>/SKILL.md` — skills are discovered from the filesystem; `plugin.json` carries **no** skill list.
2. `plugins/soleur/commands/help.md` — the real source. `plugins/soleur/skills/help/SKILL.md` is `user-invocable: false` and reads the command file. **Note:** help.md carries no static per-skill list — Step 2 counts via Glob and Step 3 says "List all skills found with brief descriptions", so a new skill is auto-listed. "Add it to help.md" therefore means adding it to the **named** flow/capability block, not to an inventory.
3. `plugins/soleur/commands/go.md` — routing row, inside `<!-- eval-gate:block:go-routing:start/end -->` (`:159-171`).
4. `plugins/soleur/lib/workflow-fidelity.ts` — `PIPELINE_SKILLS` (:14-19), `BRAINSTORM_CHILD_SKILLS` (:24), `PLAN_PIPELINE_PREFIX` (:27), `IMPLEMENTATION_TAIL` (:30-36), `ONE_SHOT_CHILD_SKILLS` (:39-42), `HANDOFF_SKILLS` (:45), `POST_MERGE_VERIFICATION_SKILLS` (:50), `GO_SKILL_ROUTES` (:89-97), `mandatorySuccessors()` (:112).
5. `plugins/soleur/test/components.test.ts:21` — description word budget.
6. README counts via `soleur:release-docs` → `bash scripts/sync-readme-counts.sh` (root `README.md`, `plugins/soleur/README.md`) + a manual `plugin.json` description edit + `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` + `npx @11ty/eleventy` verification.
7. A **named predecessor** that invokes it (the orphan-skill guard from the operator contract).

### The `/go` eval gate — what an edit actually costs

- Registry: `plugins/soleur/skills/eval-harness/gated-skills.json` holds exactly four targets. `plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh:57` **pins the set** to `{go-routing, incident-threshold, lane-inference, ticket-triage}` — no new gated target may be added.
- `go-routing` is already registered in all three maps (`gated-skills.json:4-8`, `scripts/eval-gate.cjs:39`, `scripts/gen-skill-prompt.cjs:31`), so the three-map drift class does **not** apply here; we are editing an existing block, not adding a target.
- **A new route token is not free.** `plugins/soleur/skills/eval-harness/enums/go-routes.json` carries 8 tokens, and `plugins/soleur/skills/eval-harness/test/parse-label.test.sh:111` **and** `:113` both assert the loaded enum length is exactly `8`. A row introducing a new token reddens both lines, needs a golden task in `tasks/go-routing.jsonl` (currently 8), and needs the projection `prompts/go-skill.txt` regenerated. A real run is ≈144 API calls at `--repeat 3` (`eval-harness/SKILL.md:28`).
- **Pre-existing drift found:** the `go.md` table has **nine** rows but the enum has **eight** — `drain-prs` is in the table (`go.md:164`), in `GO_SKILL_ROUTES` (`workflow-fidelity.ts:93`) and in the projected prompt (`prompts/go-skill.txt:8`), but **absent from `enums/go-routes.json`**. A live `drain-prs` classification is out-of-enum and would fail `gate-classification` (`eval-harness/test/gate-classification.test.sh:65` proves out-of-enum ⇒ fail). Disposition in Decision D4.

### The ship PR-body gate — exact shape

- `plugins/soleur/skills/ship/SKILL.md` Phase 6 begins at `:1660`; the body template is emitted at `:1773` and `:1876` as `## Summary` → `Closes #N` → `Filed: #A #B #C` → `## Changelog` → `## Test plan` → the generation footer. `## Model Dissents (informational)` is folded in at `:1768`.
- The gate is `.claude/hooks/ship-operator-step-gate.sh`, a **PreToolUse(Bash)** hook on `gh pr ready` / `gh pr merge --auto` (`:2`). Its detector (`:136-141`) is
  `DETECT_RE="^[[:space:]]*([-*]|[0-9]+\.)[[:space:]]+(\[[[:space:]xX]\][[:space:]]+)?(\*\*)?(${GROUP_A}|${GROUP_B}|${GROUP_C}|${GROUP_D})"`,
  with `GROUP_A` covering `Operator:` / `Operator <verb>` / `manual gate` / `post-merge operator`, `GROUP_B` `T+<N><unit>`, `GROUP_C` `Within <N><unit> …`, `GROUP_D` `AC-PM<N>`.
- **The anchor is a list-bullet marker, not a heading.** That is why `## Model Dissents (informational)` is safe and why `## Merge Danger` is too. The live constraint is on the section's **bullets**: no bullet may lead with a Group-A/B/C/D token.
- **Adjacent, not duplicate:** `ship/SKILL.md:138-175` "Phase 1.5: Review Evidence Gate" ranks signals by reliability but answers *"did `/review` run?"* — not *"what evidence should the body show?"*. `plugins/soleur/skills/review/SKILL.md:438-450` already grades evidence adequacy by surface reversibility and `qa/SKILL.md:191,208` already makes screenshots the evidence unit. The new tier list must cross-reference these, not compete.

### Shell-suite registration (orphan-suite trap)

`scripts/test-all.sh` `SUITE_GLOBS` (`:78-89`) registers exactly: `plugins/soleur/test/*.test.sh`, `plugins/soleur/skills/*/test/*.test.sh`, `plugins/soleur/scripts/*.test.sh`, `.claude/hooks/*.test.sh`, `.claude/hooks/lib/*.test.sh`, `apps/cla-evidence/scripts/*.test.sh`, `apps/web-platform/scripts/*.test.sh`, `apps/web-platform/scripts/lib/*.test.sh`, `scripts/lib/*.test.sh`.

Two absences are load-bearing and both are documented in the file:

- `plugins/soleur/skills/*/scripts/*.test.sh` is **deliberately** not registered (`:72-76`).
- `plugins/soleur/scripts/lib/*.test.sh` is **not** registered — shell globs do not cross `/`, the exact class that left `freeze-lock.test.sh` ungated until #7409 (`:82-84`).

`scripts/lint-orphan-test-suites.sh` diffs `git ls-files '*.test.sh'` against those globs; measured baseline on this branch: `walked 465 tracked *.test.sh against 6 registration surfaces — 465 covered, 0 orphaned`. Any new shell suite must land on a **registered** glob or the lint reddens.

### Other measured repo facts

- Canonical sibling-source idiom: `plugins/soleur/scripts/domain-model-drift.sh:25-27` —
  `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, then `# shellcheck source=…`, then `source "$SCRIPT_DIR/lib/…"`.
- `scripts/sync-readme-counts.sh:43` counts commands with `find "$PLUGIN_DIR/commands" -type f -name "*.md"` — **recursive**. A reference file under `plugins/soleur/commands/` would inflate the command count and drift both READMEs. Reference bodies therefore live under `plugins/soleur/skills/<skill>/references/` (the established convention; `discoverSkills()` globs `**/SKILL.md`, so a `references/` sibling is never counted as a skill).
- The four `provision-*.sh` scripts have **zero** dedicated tests under `plugins/soleur/test/`.
- Attribution precedent: `plugins/soleur/NOTICE` (6127 bytes) carries per-source entries with upstream URL, "Used in:", "Portions adopted:" and the full licence text; skills point at it — `plugins/soleur/skills/code-to-prd/SKILL.md` uses `_Adapted from <repo> (MIT) — see [plugins/soleur/NOTICE](../../NOTICE)._` and `plugins/soleur/skills/frontend-anti-slop/references/anti-patterns.md` uses an HTML-comment form. `hr-third-party-content-grep-on-undertaking` additionally requires grepping the diff for the third party's content before PR-ready.
- `disable-model-invocation` is used by **no** Soleur skill today; the invocation axis is bundle 4's scope (#8290). `operator-explain` therefore ships without that key (Decision D5).

### Institutional learnings that change a decision

| Learning | Constraint it imposes |
|---|---|
| `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` | Measure at plan time (done: 2442/2442) and carry exact trim-or-bump text into the plan. |
| `knowledge-base/project/learnings/2026-02-22-skill-count-propagation-locations.md` | Skill count lives in 5+ files, not just `plugin.json`; `release-docs` + `sync-readme-counts.sh` is the sweep. |
| `knowledge-base/project/learnings/2026-05-19-ship-message-no-operator-checklist.md` | The new PR-body section must not reintroduce a prose operator checklist; auto-execute or file a tracked issue carrying `auto_command:`. |
| `knowledge-base/project/learnings/2026-05-29-agents-byte-budget-trim-from-rationale-not-directive.md` | When amending a rule body, trim from `**Why:**` narrative, never from the directive. |
| `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` | Under `set -euo pipefail`: bare `$N` → `${N:-}`; pipelines inside `$( )` need `\|\| true` when a zero-match is legitimate; test the zero-arg and zero-match paths. |
| `knowledge-base/project/learnings/2026-07-18-forbiddance-drift-guard-encodes-pre-refactor-threat-model.md` | A guard must assert the GOOD form exclusively, not blacklist the removed bad form. Litmus: name a reasonable next implementation that satisfies the assertion while violating the property. |
| `knowledge-base/project/learnings/2026-06-29-eval-gate-target-validity-and-three-map-drift.md` | Verified **not** to apply — `go-routing` is already in all three maps. Recorded so a later reader does not re-derive it. |

### Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 65 issues; a `jq … contains($path)` sweep over every candidate path in `## Files to Create` / `## Files to Edit` returned zero matches. Re-run at `/work` time if the file list grows.

## Decisions

Recorded here because each one bounds the implementation and several reverse what the issue body proposed.

### D1 — Extract the library from in-repo prior art; do not port `template.sh`

The peer `template.sh` is 204 lines implementing six primitives. Five already exist in this repo (Cut List). Porting would add a **sixth** copy of the `.env` upsert that is already duplicated four times. The library is therefore **assembled by extraction**, with one genuinely new primitive (cross-platform URL opening covering macOS `open` and WSL `wslview`/`explorer.exe`, where in-repo prior art is `xdg-open`-only).

The peer's contribution that *is* adopted is the **shape**: an immutable library above a `STAGES` marker with only the stages authored below it, and the "never hand-edit the library" invariant. That is prose, so the attribution comment is required in every file that takes it.

### D2 — Automation-first generated scripts, with a **closed set of two** interactive carve-outs

An earlier draft of this decision proposed "interactive mode reserved for credential entry only". The CTO assessment falsified it, and the correction matters: that carve-out is too narrow and would force the refactor to **delete five existing acknowledgement gates** — `provision-cloudflare.sh:214`, `provision-doppler.sh:226`, `provision-github.sh:239` and `:274`, `provision-hetzner.sh:113` — each of which exists because `hr-menu-option-ack-not-prod-write-auth` mandates a per-command confirmation for a destructive write against shared production, and says explicitly that a menu ack does not extend to a new command. `provision-hetzner.sh:118` creates a real billable server.

There is also no collision with `hr-multi-step-post-merge-bootstrap-script` once its trigger is read precisely: it fires on a **post-merge deferral event** and governs the artifact a ship emits. It is not a general "all repo bash is non-interactive" rule. And `hr-exhaust-all-automated-options-before` ends with *"prompt for creds not in Doppler"* — credential prompting is **inside** the ladder, not an exception to it.

**The contract, which is the real deliverable:**

- **Closed set of exactly two interactive carve-outs.** (1) Credential **entry** — `hr-never-label-any-step-as-manual-without` ("CAPTCHA, credential ENTRY (login/2FA/payment), or admin-scoped mint") plus `hr-exhaust-all-automated-options-before`. (2) Per-command **destructive-write acknowledgement** — `hr-menu-option-ack-not-prod-write-auth`. A third carve-out requires an ADR amendment.
- **Total non-interactive path.** For every prompt there exists a named environment variable that, when set, skips it. When stdin is not a TTY **and** the variable is unset, the script exits **64** naming the missing variable, *before* reading. Never a hang. `64` is already this repo's convention at `apps/cla-evidence/infra/bootstrap.sh:77,81,87`. Today's behaviour is fail-closed but **mute**: `provision-hetzner.sh:113-114` reads EOF into an empty `ACK` and exits 1 with `"Aborted."` — right outcome, unattributed cause.
- **Ladder order before any prompt.** Environment variable → Doppler → MCP/CLI/REST. A value outside the two carve-outs that is missing is a hard failure with a named remedy, never a prompt. This is what stops the generator becoming a route around `hr-all-infrastructure-provisioning-servers`.

### D3 — Placement is already decided by ADR-178; the test path costs zero registration edits

`knowledge-base/engineering/architecture/decisions/ADR-178-shared-bash-primitives-ship-in-plugin.md` §Decision §1 is directly on point: a shared bash primitive consumed by shipped plugin code lives **inside `plugins/soleur/`**, and names `plugins/soleur/scripts/lib/` as the pattern.

- **Library: `plugins/soleur/scripts/lib/operator-script.sh`.** Siblings there are `proc.sh`, `domain-model-lib.sh`, `session-state.sh`.
- **Rejected — a skill-local library** under `skills/operator-bootstrap/scripts/`: consumers span four different skills, so it would source across a sibling-skill boundary — the same cohesion inversion ADR-178 §1 used to reject `plugins/soleur/hooks/lib/`.
- **Rejected — the `_*.sh` prefix.** That convention is local to `apps/cla-evidence/scripts/`; nothing in `plugins/soleur/scripts/lib/` uses it. What transfers from `_cf-admin-token.sh` is `# shellcheck shell=bash` as line 1 and the explicit sourcing-preconditions block (`:12-19`).
- **Rejected — the name `wizard-lib.sh`.** "Wizard" is the peer repo's vocabulary imported wholesale; the shipped siblings are plainly named.
- **Test: `plugins/soleur/test/operator-script.test.sh`**, resolving the library through `$SCRIPT_DIR/../scripts/lib/`. This is exactly the ADR-178 library's own precedent — `plugins/soleur/test/session-state.test.sh:2,10` tests `plugins/soleur/scripts/lib/session-state.sh` from that path, and `scripts/test-all.sh:77` already registers the glob. **No `SUITE_GLOBS` edit.** Adding `plugins/soleur/scripts/lib/*.test.sh` would be actively harmful: `scripts/test-all.sh:69-74` documents that a glob matching nothing "makes a future suite auto-register without anyone deciding to."

### D4 — No `go.md` edit at all; the `drain-prs` enum drift is fixed inline behind a parity guard

Two independent lines of reasoning converge on leaving `go.md` untouched.

**Routing.** `/go` classifies **work requests**. `operator-bootstrap` is invoked by `ship` and by the `provision-*` skills, not typed by a founder describing work. `operator-rephrase` is a conversational corrective, not a work request. Both are **deliberately not routable from `/go`**, stated in the PR body with the named invoker, exactly as the operator contract permits. The measurements support it: a new route token widens `enums/go-routes.json` from 8, reddening `parse-label.test.sh:111` and `:113`, needs a golden task and a regenerated projection, and costs ≈144 API calls per eval run.

**Discoverability.** B12's founder-facing half moves to `help.md` (D8) and its agent-facing half moves to an `AGENTS.rules.md` rule (D9). Neither is a `go.md` edit.

So no edit lands inside `<!-- eval-gate:block:go-routing:start/end -->` and the gate does not fire. That claim is **produced as evidence, not asserted**: `node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --check plugins/soleur/commands/go.md` plus a byte-identity assertion of the gated block against `origin/main`, and a `--dry-run --target go-routing` that spends no API budget. All three outputs attach to the PR body.

The audit did surface a real pre-existing defect: `drain-prs` is a live route in the table (`go.md:164`), in `GO_SKILL_ROUTES` (`workflow-fidelity.ts:93`) and in the projected prompt (`prompts/go-skill.txt:8`), but is **absent from the enum**, so a live classification of it is out-of-enum and fails `gate-classification`. Triaged inline per `wg-defer-only-after-inline-triage`: the fix is one enum entry, two literal counts in `parse-label.test.sh`, and one golden task. It is folded in **together with the parity guard that would have caught it** (Guard 1) — without the guard the next row drifts the same way.

### D5 — `operator-rephrase`, not `operator-explain`; ships model-invocable

The operator contract authorises a better name inside the shipped convention: *"If the implementing plan finds a better name inside the shipped convention, take it."* Two reasons to take it here:

- The shipped `operator-*` family is really `<audience>-<artifact>` — `operator-digest`'s second token names the artifact. `explain` under-describes the trigger: the founder did not fail to receive an explanation, the message did not land, and the action is re-saying the **same** content in a different register. "Explain" invites a lecture; "rephrase" invites a restatement.
- `operator-bootstrap` keeps its proposed name unchanged, because `hr-multi-step-post-merge-bootstrap-script` already mandates the artifact `<feature>/bootstrap.sh` — the rule-to-skill word match is the point.

This is a deviation from the name table in the issue, so it is also recorded in `knowledge-base/project/specs/<branch>/decision-challenges.md` for the operator to see and reverse with a single rename if they prefer.

**Invocation axis.** The peer skill sets `disable-model-invocation: true`. No Soleur skill uses that key today and the invocation axis is bundle 4's declared scope (#8290). Shipping it here would pre-empt that bundle's decision across ~16 skills, so `operator-rephrase` ships without the key.

**Name-collision note.** `plugins/soleur/skills/flag-bootstrap/` exists on disk with only `SETUP.md` and no `SKILL.md`, so it is not a live skill. `/work` confirms that before landing `operator-bootstrap`, so the two do not read as a `*-bootstrap` family that is not one.

### D6 — Bump `SKILL_DESCRIPTION_WORD_BUDGET` by the measured delta, against a 2442/2442 baseline

Headroom is zero, and `cq-skill-description-budget-headroom` requires plan-time surgery below 10 words. Every prior skill addition recorded in that constant's own comment took the bump path with the baseline documented inline; trimming two unrelated siblings to pay for an unrelated feature is the worse trade. Candidate descriptions and their measured counts:

- `operator-bootstrap` — **31 words**: *"This skill should be used when post-merge steps need a runnable script, not a prose checklist. Generates an idempotent bootstrap.sh that chains every automatable step and prompts only for credential entry."*
- `operator-rephrase` — **23 words**: *"This skill should be used when the last message did not land: re-pitch it in plain controlled English using the project's own vocabulary."*

2442 + 54 = **2496**, appended to the constant's comment in the established form (`bumped +54 for #8287 (operator-bootstrap 31 + operator-rephrase 23 words, against a 2442/2442 zero-headroom baseline)`). `/work` re-measures after final wording and sets the bump to the measured delta, not to this estimate.

### D7 — Fold the naming-convention correction into `skill-structure.md`, minimally

The issue asserts the documented verb-noun convention is "a defect tracked separately in the bundle-4 issue". Measured: #8290 does not name it (its scope is the invocation axis, negation phrasing, and four authoring levers). Leaving it unowned would leave this bundle's own naming contract contradicting the repo's authoring reference. The correction is folded in and kept to the `<naming_conventions>` opening statement plus the shipped evidence, because #8290's B6 edits the same file and a larger rewrite would collide.

### D8 — B9 reshaped: Undo-first, derived from an agent that already computes it

The issue specifies a one-word `Door:` verdict. Shipped as specified, it reproduces a documented defect. `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md:184-194` records a one-way-door ruling that was **wrong** — an undo path existed the whole time — and the ADR's own words are that stating it as a one-way door *"will make an operator refuse a rollback they should take."* The defect is not a mislabel; it is a **label with no mechanism attached**. A one-word verdict is unfalsifiable; a named undo command is checkable by founder and reviewer alike.

Three corrections:

**(a) Derive it, do not invent it.** `review` already runs `deployment-verification-agent` with the lens *"Go/No-Go deploy checklist with SQL verification queries and rollback procedure"* (`plugins/soleur/skills/review/workflows/review.workflow.js:63`; described at `plugins/soleur/skills/review/SKILL.md:280`). If ship's Phase 6 independently judges reversibility, the pipeline carries **two uncorrelated reversibility claims** — the ADR-119 shape reproduced structurally. Ship quotes that agent's rollback line, and writes `none produced` when review ran degraded.

**(b) Undo first; Door derived from it.** The generated block is three fields, not one:

```
## Merge Danger
**Undo:** <exact command or action that reverses this> | none known
**Door:** two-way (undo tested) | two-way (undo untested) | one-way — <what is permanently lost>
**Blast Radius:** docs | plugin | web-platform | prod-data | money
```

`Door` cannot be written without `Undo`, so the ADR-119 failure is structurally unavailable. The qualifier is `tested`/`untested` — checkable — not a subjective confidence word.

**(c) No "when unsure, say two-way" default.** ADR-119's failure was **over**-claiming irreversibility, so the intuitive safety default is the direction that caused it; but a blanket two-way default under-claims on a live charge, a deleted volume, a published tag. The rule is directionless: **name the undo; if you cannot name one, write `one-way` and name what is lost.**

**Evidence tiers** ride in the same section and **cross-reference rather than compete**: `ship/SKILL.md:138-175` Phase 1.5 answers *"did `/review` run?"*, `review/SKILL.md:438-450` already grades evidence adequacy by surface reversibility, and `qa/SKILL.md:191,208` already makes screenshots the evidence unit. The new text ranks what the body should **show** (screenshots S-tier when the change is visual; execution-based evidence A-tier, showing the exact test that fails then passes) and points at those three as the gates that decide sufficiency.

**Gate safety.** The heading `## Merge Danger` clears the `ship-operator-step-gate` deny set the same way `## Model Dissents (informational)` does (`ship/SKILL.md:1769`): the detector anchors on a **list-bullet marker**, not a heading. The live constraint is that no bullet in the section may lead with a Group-A/B/C/D token. The section is also placed so it cannot perturb the `Filed:` line parse, which `ship/SKILL.md:1790` calls the net-issue-flow gate's only counted attribution source.

### D9 — B9 escalation blocks an existing gate; it never creates a new channel

The issue's premise — "the founder reads this before approving a merge" — is false on the majority path. `wg-verified-work-ships-without-asking` says never stop to ask permission to ship your own work, and `wg-after-marking-a-pr-ready-run-gh-pr-merge` runs `gh pr merge --squash --auto` and polls to MERGED. Merge is review-gated, not founder-gated, so a field the founder is *asked to read* before an auto-merge that fires regardless is decoration. `ship/SKILL.md:1861` already concedes *"a PR body is not an operator-visible surface."*

The Model Dissents precedent (`ship/SKILL.md:1769` — render in the body **and** open one idempotent `action-required` issue) is only half applicable: Model Dissents is retrospective, and a weekly digest is adequate delivery for a decision already taken. A merge-danger verdict is **prospective and expires at merge**. Per-PR `action-required` filing would also flood the channel the digest depends on — `operator-digest/SKILL.md:209` warns that labelling a self-heal as an ask *"spends the P1 channel's credibility."*

So the verdict is **either silent or a hold** — never a new delivery channel:

| Verdict | Delivery |
|---|---|
| `two-way` and blast radius ∈ {`docs`, `plugin`} | PR body only. No issue, no digest. Auto-merge proceeds exactly as today. |
| `one-way`, **or** blast radius ∈ {`prod-data`, `money`} | A **hold**: block `gh pr ready` / auto-merge and surface the choice, reusing the Phase 5.5 gate machinery the same way a `sequential-fallback` review on a `single-user incident` plan already blocks at `ship/SKILL.md:203`. |

### D10 — B12 splits by audience: `help.md` for the founder, one AGENTS rule for the agent

The research finding that "help.md is already a capability map" is only half right, and the correction narrows the work considerably. `help.md:67-71` **does** group agents by category with counts. `help.md:73-74` is literally `SKILLS: [N] skills` followed by `[List all skills found with brief descriptions]` — a flat, ungrouped dump of 98 items. **Agents are mapped; skills are not.** That is the founder-facing gap.

- **Founder half:** rewrite `help.md:73-74` to group skills by the prefix families the naming convention already creates (`flag-*`, `cron-*`, `provision-*`, `resolve-*`, `operator-*`, `legal-*`, `test-*`, `agent-*`, `release-*`, `drain-*`), plus one "start here" line naming `/soleur:go`. Roughly 15 lines in one file. This is also the **payoff** of the `<noun|domain>-<verb>` convention D7 defends: the convention was adopted so related skills sort together, and the help output has never rendered that grouping.
- **Agent half:** the ordered five-option phase-boundary tree is agent-facing — the founder never reads `go.md` or `AGENTS.rules.md`. It ships as **one new Communication rule** cross-referencing the three ids that already cover three of the five options (`cm-when-proposing-to-clear-context-or`, `wg-end-of-work-emit-resume-prompt`, `cm-delegate-verbose-exploration-3-file`). The new content is the ordering, **Continue** ruled out first (it costs nothing and loses nothing), and **`/compact` placed last** as the default rather than the first reach. The full reasoning lives in a reference file, per the ADR-151 index/body split.

Consequence: **no `go.md` edit for B12**, which is the second independent reason the eval gate does not fire (D4).

### D11 — Scope: the four-script refactor is reduced to one proving consumer

Both the CTO and CPO assessments independently recommended splitting this issue into multiple PRs, and both identified the same piece as the risk: the four-script refactor is week-plus work against 1041 lines with **zero test coverage** and live Cloudflare / Doppler / GitHub / Hetzner credentials.

A one-shot run produces one PR, so this plan reduces scope rather than splitting delivery:

- **In scope:** characterization tests for **all four** provision scripts (they have none today, and they are the safety net the refactor needs), plus the refactor of **`provision-hetzner.sh` only** — the smallest at 155 lines, with a `--dry-run` path — as the proving consumer that keeps the library from shipping inert (`knowledge-base/project/learnings/2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`).
- **Deferred to a filed follow-up issue:** `provision-cloudflare.sh`, `provision-github.sh`, `provision-doppler.sh`, in that order of ascending blast radius. Doppler is deliberately last: its prologue at `:4-13` explains why the *conditional* xtrace arm is vacuous by construction there (the token is acquired by `read -rs` **below** the guard, so the variable is empty at guard time), and `:21-27` unsets `SSLKEYLOGFILE` / `CURL_CA_BUNDLE` / `SSL_CERT_*` — bespoke and load-bearing. A generic library guard would reintroduce exactly the arm #7797 removed.

This narrows the issue's stated Fix-Size, so it is recorded in `decision-challenges.md` as a User-Challenge rather than applied silently.

### D12 — The library must not absorb the `read -rs` call site

`plugins/soleur/skills/incident/test/redact-sentinel.test.sh:1206-1210` **pins `skills/provision-hetzner/scripts/provision-hetzner.sh` as a required member** of a credential-acquisition discovery set, precisely because its `read -rs` at `:123` is one of three deliberately distinct acquisition mechanisms. The anti-vacuity comment at `:1197-1205` explains that membership, not a count, is asserted, and the failure message at `:1221` says the zero-violation verdict below it would be vacuous if the predicate stopped seeing any of the three.

Moving `read -rs` into the sourced library drops `provision-hetzner.sh` out of that set and fails Test 24. So: **the prompt stays in the caller.** The library supplies the surround — xtrace refusal, TTY detection, environment-variable skip, output masking. That is the better factoring regardless, because the prompt string is the operator-facing product.

### D13 — `operator-rephrase` cites its register, ships with no vocabulary source, and does not claim standard conformance

- **Register: point, do not restate.** `plugins/soleur/skills/operator-digest/SKILL.md:23-28` already defines it. A third copy would be two too many — `knowledge-base/marketing/brand-guide.md` Tone Spectrum carries a second. The skill says "Register: as defined in `operator-digest/SKILL.md` §Register" and adds only the **delta**: single message, synchronous, and *not* bound by the digest's "every line states a business consequence or it is cut", which is a digest rule that would mangle an in-the-moment restatement of a technical fact.
- **No vocabulary source in v1.** `plugins/soleur/docs/pages/glossary.njk` is disqualified three ways: it is marketing surface with `seoTitle` / `permalink` frontmatter (`:2-6`); its ten entries are category terms (Company-as-a-Service, agentic engineering, MCP, vibe coding) rather than the operational vocabulary a founder trips on mid-session (worktree, draft PR, auto-merge, compaction, squash); and it is Nunjucks with `{{ }}` interpolation, unreadable as plain text without an Eleventy build. `kb-glossary` arrives in bundle 3 (#8289), **after** this one, so the dependency is filed forward — a scope line added to #8289 — rather than stubbed backward here.
- **ASD-STE100: cite the discipline, do not claim conformance.** `grep -rn "ASD-STE100\|Simplified Technical English\|controlled English" plugins/ knowledge-base/` returns zero. There is no controlled vocabulary to bind to and no gate that could check conformance, so a seven-line skill *claiming* conformance to a controlled-language standard is false precision. The skill instead names the discipline as its influence and states the checkable parts: short sentences, one idea per sentence, active voice, no jargon, no file paths, no issue numbers. This narrows the issue's wording, so it is recorded in `decision-challenges.md`.
- **Path correction:** the live brand guide is `knowledge-base/marketing/brand-guide.md`. It is **not** under `knowledge-base/overview/`, which contains only `vision.md` — any citation pointing there is stale and must be corrected rather than followed.

### D14 — One ADR, extending ADR-178

ADR-178 already decided placement and move-not-duplicate; restating it would be redundant. The ADR-worthy decision is the **generated-artifact contract** — a cross-cutting invariant with no single-file trigger, which is what `cq-agents-md-tier-gate` calls ADR-eligible. Provisional ordinal **ADR-226**: the highest on `origin/main` is ADR-224 and ADR-225 is already claimed on a pushed branch (enumerated across all 89 `origin/*` refs, not just `main`). The ordinal is provisional and re-derived immediately before merge.

## User-Brand Impact

- **If this lands broken, the user experiences:** a generated `<feature>/bootstrap.sh` that runs partway, writes a half-populated `.env` and a partially-set GitHub secret set, then exits — leaving the founder's repo in a state that neither the script's re-run path nor the prose runbook it replaced can recover, because the script is now the only description of what step 4 of 9 was.
- **If this leaks, the user's credentials are exposed via:** the generated `.env` written at the shell's default umask into a directory that may sit under a cloud-sync client — a `0644` `.env` holding `HCLOUD_TOKEN` / `DOPPLER_TOKEN`. Vector: file mode. Control: `umask 077` inside the immutable library, and `chmod 600` asserted after every upsert (the shape already at `community/scripts/linkedin-setup.sh:452-454`).
- **If this leaks, the user's credentials are exposed via:** `gh secret set NAME --body "$TOKEN"` — the value lands in `/proc/<pid>/cmdline`, readable by every process on the machine, and in shell history when re-run by hand. Vector: process argv plus shell history. Control: the library exposes only the stdin form, mirroring `operator-digest/scripts/provision-operator-digest-repo.sh:70-73`; the `--body <value>` form is banned above the marker.
- **If this leaks, the user's credentials are exposed via:** a stage that echoes a variable for progress, or a run under `set -x` — the token reaches stdout, which in a Claude Code session is captured into the transcript. This is the documented `hr-never-paste-secrets-via-bang-prefix` leak path, whose **Why** cites a live prd-JWT leak on 2026-05-06. Control: the xtrace refusal (exit 78) plus the rule that a stage never echoes a secret variable, which `scripts/lint-shell-trace-credential-refusal.py` already enforces and Guard 5 keeps in scope. **R5:** an earlier draft added a secret-value registry and an output-scrubbing EXIT trap on top of this. Cut — an output-rewriting trap fails open on SIGKILL (the same limitation this plan already concedes for the hetzner teardown trap), and it duplicates a lint that runs in CI where the trap cannot.
- **If this leaks, the user's credentials are exposed via:** a third-party CLI that dumps unrelated secrets as a side effect of a write — the exact case `.claude/hooks/doppler-secrets-delete-redirect.sh` already blocks. Vector: third-party CLI stdout. Control: the library's secret-write helper redirects that output and verifies with a separate read; generated stages inherit it and never re-decide.
- **Brand-survival threshold:** `single-user incident`

**Why the threshold is survivable by construction, not by review diligence.** All five controls live **above the `STAGES` marker**, in the region the authoring skill is forbidden to edit. Each generated script inherits them without re-deciding anything. That is the strongest property the architecture has, and it is the reason the immutable-library shape is adopted rather than a per-script checklist.

**Consequence carried into the implementation:** because the library becomes the only secret-writing path, `hr-write-boundary-sentinel-sweep-all-write-sites` applies — every write site in the scripts being touched is swept, not only the new template.

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-226 — "Generated operator scripts are non-interactive by default, with two named interactive carve-outs."** Relationship to ADR-178: **extends**. This is an in-scope implementation task, not a follow-up.

`## Decision` must cover, each cited to its rule:

1. The total non-interactive path: every prompt has a named environment variable; no TTY plus unset variable ⇒ exit **64** naming the variable, before reading; never a hang.
2. The **closed set of two** carve-outs — credential entry (`hr-never-label-any-step-as-manual-without`, `hr-exhaust-all-automated-options-before`) and per-command destructive-write acknowledgement (`hr-menu-option-ack-not-prod-write-auth`). A third requires an amendment to this ADR.
3. `open_url` is **additive only**: print the URL first, open best-effort, never branch on the exit code — the shape already at `community/scripts/linkedin-setup.sh:322-333`. Note that `hr-never-label-any-step-as-manual-without` requires a prior Playwright attempt before any browser step is called operator-only.
4. **The `read -rs` call site stays in the caller**, citing `incident/test/redact-sentinel.test.sh:1206-1210` as the reason, so the next refactor does not delete it.
5. "Never hand-edited" is a **gate, not a comment**: a generated-file header marker plus a regeneration-parity test (Guard 2).
6. Placement defers to ADR-178 §1; test placement follows the `session-state.test.sh` precedent, with the reason stated (no new `SUITE_GLOBS` entry, per `scripts/test-all.sh:69-74`).
7. The five secret-handling controls from `## User-Brand Impact` are library invariants above the marker.

`## Alternatives Considered` must cover:

- **A — Port the peer wizard's interactive-first shape.** Rejected: hangs with no TTY under `one-shot` and CI; its browser step conflicts with `hr-never-label-any-step-as-manual-without` absent a prior Playwright attempt.
- **B — Non-interactive only, zero carve-outs.** Rejected: would delete five acknowledgement gates and violate `hr-menu-option-ack-not-prod-write-auth`. This is the alternative the first draft of D2 was nearest to; record why it lost.
- **C — Skill-local library.** Rejected on ADR-178 §1's cohesion argument: five consumers across four skills.
- **D — Repo-root `scripts/lib/`.** Rejected: ADR-093 / ADR-178 — `marketplace.json` ships `./plugins/soleur` only.
- **E — Status quo duplication.** Rejected with the measured numbers: `.env` upsert 4×; xtrace prologue present in 1 of 4 credential-handling scripts.

### C4 views

**No C4 impact**, and the enumeration backing that conclusion was run against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`), not a keyword grep:

- **External human actors:** the only actor is the existing solo founder/operator, already modelled. The change adds no correspondent, reviewer or recipient.
- **External systems / vendors:** Cloudflare, Doppler, GitHub and Hetzner are all already modelled as external systems; this change adds no vendor and moves no boundary. The generated script calls the same vendors the existing `provision-*` scripts already call.
- **Containers / data stores:** none added. The generated `.env` is a file on the founder's own machine, outside the modelled system boundary.
- **Actor↔surface access relationships:** unchanged. No ownership or tenancy boundary moves; no sharing model changes.

Because `model.c4` embeds derived cardinalities that the actor/system rubric does not reach, the conclusion is additionally backed by a green run of `plugins/soleur/test/c4-count-parity.test.sh` — that run is an acceptance criterion, not a reasoning step.

### Sequencing

The decision is true the moment the library lands, so the ADR is authored at `status: accepted` in the same PR. No soak gate applies.

## Infrastructure (IaC)

**Skipped — no new infrastructure.** This change introduces no server, systemd unit, cron job, vendor account, DNS record, TLS certificate, secret or firewall rule. It refactors existing shell that *emits* Terraform recipes; the emitted recipes are unchanged in content. The plan draft and the issue body were scanned against the full Phase 2.8 detection set — remote-shell invocations, service-manager commands, secret-store writes, state-import commands, vendor-dashboard wording and new scheduled jobs — and **every one of those classes returned zero matches**.

One design constraint exists precisely to keep it that way: D2's ladder rule means a value outside the two carve-outs that cannot be resolved automatically is a **hard failure with a named remedy, never a prompt**. Without that rule the generator would become a sanctioned route around `hr-all-infrastructure-provisioning-servers`.

## Observability

Layer **7 — `cli-stdout-artifact`** (`plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`, layer-7 paragraph). Two constraints from that text are binding here:

- **Stdout alone is an explicit P1 rejection.** A layer-7 citation must pair the synchronous stdout marker with a **durable committed artifact** carrying the same fields, because stdout does not survive the session.
- **Sentry / Better Stack are deliberately NOT wired, and that is a decision rather than an absence.** The generated script runs on the founder's own machine; the same paragraph holds that routing a self-hosted run's output to Soleur infrastructure is a data-controller event requiring explicit consent, not an observability improvement. The **generator skill** under `plugins/` is a separate surface — vendored into the production image and also run hosted — so both answers are given.

```yaml
liveness_signal:
  what: >
    Each generated script appends one JSON line per stage to an append-only run ledger at
    provisioning/<slug>/bootstrap-runs.jsonl (or .soleur/bootstrap-runs.jsonl when no slug),
    carrying run_id, stage_index, total_stages, stage_name, outcome, exit_code, and the
    NAMES (never values) of any env keys and GitHub secrets written.
  cadence: one line per stage, written before the stage acts and again after it settles
  alert_target: >
    none - deliberately. The surface is the founder's own machine and routing it to Soleur
    infrastructure is a data-controller event, not an observability improvement.
  configured_in: plugins/soleur/scripts/lib/operator-script.sh (above the STAGES marker)
error_reporting:
  destination: >
    stdout SOLEUR_BOOTSTRAP_* markers for the live run, PLUS the durable run ledger above.
    Markers go to STDOUT, not stderr - provision-doppler.sh:12-13 records the reason:
    agent runtimes surface stdout and swallow stderr, so a stderr-only refusal is invisible
    on the one surface that matters.
  fail_loud: true
failure_modes:
  - mode: silent hang because stdin is not a TTY and the skip variable is unset
    detection: SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=<NAME> tty=0 emitted BEFORE the read, then exit 64
    alert_route: local - the ledger records the attempt, so absence of the line is itself diagnostic
  - mode: library not found, script degrades to a no-op stub
    detection: SOLEUR_BOOTSTRAP_LIB_MISSING path=<resolved> then a hard exit, never a stub
    alert_route: local - ADR-178 Context section 1's defect verbatim, where fail-closed stubs made cleanup-merged refuse to reap forever
  - mode: a credential reaches the terminal or the agent transcript
    detection: xtrace refusal exits 78 with the marker on stdout
    alert_route: local, plus scripts/lint-shell-trace-credential-refusal.py at CI time
  - mode: partial provisioning - stage N succeeded, N+1 failed, live billable resources orphaned
    detection: >
      the ledger's set of COMPLETED stage indices is compared against the TOTAL_STAGES the script
      declares in its own header; any gap is a partial run. R4 - an earlier draft detected this as
      "the last line has no matching settle record", which is undecidable: that line would be
      written by the process that was killed, so its absence is indistinguishable from never-ran,
      deleted-by-the-founder, and a different slug directory. Comparing a completed-set against a
      declared total is decidable from the artifact alone.
    alert_route: local - provision-hetzner.sh:118 creates a real billable server and the trap at :127 does not survive SIGKILL, so stdout cannot carry this
  - mode: an .env upsert clobbered an adjacent key sharing a prefix
    detection: the ledger records key names written plus the pre-write key count; a drop is diffable after the fact
    alert_route: local
  - mode: a generated script was hand-edited and drifted from its generator
    detection: the generated-file header marker plus the regeneration-parity test (Guard 2)
    alert_route: CI - without the guard this mode has no detector at all
logs:
  where: >
    bootstrap-runs.jsonl in the FOUNDER's repository, which is where layer 7's
    "committed to the customer's own repository" condition is satisfied. R24 - both candidate
    paths are gitignored in THIS repo, so the artifact is never committed here; saying so
    plainly is the difference between citing the layer and meeting it. The generator skill's
    own hosted runs surface in the existing plugin CI logs; no new sink is created.
  retention: append-only, operator-controlled; nothing self-expires and nothing is transmitted
discoverability_test:
  command: bash plugins/soleur/test/operator-script.test.sh
  expected_output: >
    The suite's own trailing summary line and exit 0. R13/R24 - an earlier draft declared
    verify-bootstrap-run.sh --self-test here. That mode is cut: it duplicated this suite, and
    its "12/12 invariants OK" pinned a hard-coded count in an expected-output string, which is
    the frozen-list defect this plan's own guards forbid elsewhere. This suite already satisfies
    the probe-verb gate (first token `bash`, second a repo-relative path), needs no prior run,
    no network and no credentials. verify-bootstrap-run.sh survives with --ledger <path> --last
    only, which prints the last run's stage ledger and exits non-zero when that run is
    incomplete.
```

The first token is `bash` and the second a repo-relative path, satisfying preflight Check 10's `PROBE_VERB_ALLOWLIST`. No `credentials_required` declaration is needed: every property the probe asserts has an unauthenticated substitute.

A second probe, needing no prior run and nothing configured, proves D2's no-TTY contract directly: `</dev/null timeout 10 bash <generated>/bootstrap.sh; echo "exit=$?"` must print `exit=64` and a `SOLEUR_BOOTSTRAP_INPUT_REQUIRED` line.

### Soak Follow-Through Enrollment

Not applicable. No acceptance criterion and no liveness signal is time-gated; nothing here closes on a post-deploy soak.

## Encryption Posture

The Phase 2.11 detection set (`.tf`, `supabase/migrations/*.sql`, `cloud-init*.yaml`, `docker-compose*.yaml`) does **not** match this change, and no persistent store or cross-component connection is introduced. The section is written anyway because the library becomes the sole writer of a secret-bearing file on the founder's disk, and silence there would be the wrong kind of honest.

```yaml
at_rest:
  - store: the generated .env on the founder's own machine
    mechanism: filesystem permissions only - mode 0600 under umask 077; no encryption at rest
    evidence: >
      chmod 600 asserted AFTER the mv that completes each upsert, because mv replaces the
      inode and its mode (the reason linkedin-setup.sh:452 sits after the mv at :448, not
      before it). Guard 3 drives a mutation that moves the chmod before the mv.
    defends_against: another local user account reading the file; a backup or cloud-sync client copying it at a default 0644
    does_not_defend: root on that machine; full-disk compromise; a malicious process running as the founder; anything after the founder copies the value elsewhere
    disclosed_as: >
      stated in the generated script's own header and in operator-bootstrap/SKILL.md, so the
      founder is told what the file is and what protects it
    live_verification: stat -c %a provisioning/<slug>/.env returns 600
in_transit:
  - connection: the generated script to GitHub, for the gh secret and gh variable writes
    tls: yes - delegated wholly to the gh CLI; the library adds no transport of its own
    cert_verification: on
    does_not_defend: a compromised gh credential; a trusted-but-hostile CA already in the OS store
    disclosed_as: no new sub-processor and no new endpoint - the same GitHub API the repo already calls
  - connection: the generated script to Cloudflare / Doppler / Hetzner, via each vendor CLI or curl
    tls: yes
    cert_verification: >
      on, and load-bearing: the prologue unsets SSLKEYLOGFILE, CURL_CA_BUNDLE, SSL_CERT_FILE
      and SSL_CERT_DIR before any credentialed call, so an attacker-supplied CA bundle cannot
      be honoured. provision-doppler.sh:21-27 documents the hole this closes; the first
      credentialed call it protects is the Bearer-token curl at :260-263.
    does_not_defend: a compromised vendor token; a CA already trusted by the OS store
    disclosed_as: unchanged from today's provisioning path
```

No `exception:` block: no store uses a plaintext exception and no connection has certificate verification off.

## Guard Contract

Five guards. Each mutation matrix is derived from the **design**, not from the implementation as it happens to be shaped, and is written before the guard.

### Guard 1 — `/go` routing-table ↔ enum ↔ dispatch-map parity

**Property.** Every intent token appearing in the `go.md` eval-gated routing table is a member of `enums/go-routes.json` and resolves to a registered target, and no member of the enum is absent from the table.

**Assembly.** The chokepoint is the **eval-gated block itself**, parsed at test time from `plugins/soleur/commands/go.md` between `<!-- eval-gate:block:go-routing:start -->` and `:end` — never a hardcoded name list. Quantified over three artefacts: that block's first table column; `plugins/soleur/skills/eval-harness/enums/go-routes.json`; and `GO_SKILL_ROUTES` ∪ `GO_AGENT_ROUTES` from `plugins/soleur/lib/go-routing.ts`. Discovery is a **census** with a red *unclassified* bucket: any token in any of the three not classified into all three reddens. `MIN_CASES` is the current nine rows — a floor, not the definition. Host: `plugins/soleur/test/go-routing-golden-path.test.ts`, which already loads `GO_ENUM` (`:34`) and `GO_SKILL_ROUTES` (`:10`).

**Mutation matrix.** Each row MUST drive the guard RED.

| # | Mutation (MUST drive RED) | Why |
|---|---|---|
| 1 | Remove `"drain-prs"` from `enums/go-routes.json`, restoring today's state | This is the live defect; a guard green on it proves nothing |
| 2 | Add a **tenth** table row whose token is absent from the enum | The census must catch the *next* drift, not only the known one |
| 3 | Add an enum token that appears in no table row | The property is bidirectional; a one-directional check passes on enum bloat |
| 4 | Point a table row at a skill absent from `GO_SKILL_ROUTES` and `GO_AGENT_ROUTES` | A row that classifies but cannot dispatch is the same defect one layer down |
| 5 | Replace the block-parse with a hardcoded nine-name array (**own-dispatch row**) | A guard that stops discovering and reports "9 checked" against a frozen list is vacuous |

**Harness rows.** (a) Delete the `expect` inside the census loop but keep the loop — the suite must redden, proving the assertions are not decorative. (b) Must-PASS non-canonical: a table carrying a **tenth** row whose token is present in the enum *and* in `GO_SKILL_ROUTES` must pass, proving the guard permits legitimate growth rather than pinning today's nine.

**Anchor.** The guard compares three artefacts one diff can edit together, so byte parity proves consistency, not integrity. Integrity comes from outside the commit: the table lives inside `eval-gate:block:go-routing`, so widening it requires a `soleur:eval-harness` verdict produced independently. An additional assertion pins the **byte identity** of the gated block against `origin/main` for this PR, so D4's "no gated edit" claim is machine-checked rather than asserted.

### Guard 2 — a generated script never drifts from its library

**Property.** The region of every generated script above the `STAGES` marker is byte-identical to `plugins/soleur/scripts/lib/operator-script.sh`, and every generated script declares which library revision produced it.

**Assembly.** The chokepoint is the **marker**, not a file list: the guard walks every file carrying the generated-file header marker (`git grep -l` over the marker literal), splits at the `STAGES` line, and compares the upper region. Unclassified bucket: a file carrying the header but **no** marker line reddens rather than being skipped.

**R3 — scoped to the committed population, deliberately.** An earlier draft swept `provisioning/` too. That directory is gitignored, so those copies never reach CI and a guard claiming to cover them would assert nothing about them — theatre with a `git grep` attached. The honest scope is generated scripts **committed to the repo** (the `operator-bootstrap` skill's "commit it only when the setup path is repeatable" case), which is exactly the population CI can see. A founder's local copy drifting is not a CI-detectable event and the plan no longer claims it is.

**Mutation matrix.** Each row MUST drive the guard RED.

| # | Mutation (MUST drive RED) | Why |
|---|---|---|
| 1 | Change one character in a generated script's library region | "Never hand-edit the library" is a comment until something checks it |
| 2 | Change `operator-script.sh` without regenerating | Drift is symmetric, and the library moving is the likelier direction |
| 3 | Add a **second** generated script that is compliant, then hand-edit only that one | A check that stops at the first file is the defect class this contract exists to catch |
| 4 | Delete the `STAGES` marker from a generated script | Without the unclassified bucket the file silently leaves the population and the guard reports fewer files, greenly |
| 5 | Make the walk return zero files (**own-dispatch row**) | A parity guard that checked nothing must not exit 0 |

**Harness rows.** (a) Replace the byte comparison with `true` — the suite must redden. (b) Must-PASS non-canonical: a generated script whose **stages region** differs completely from the template's example stages must pass, since only the region above the marker is pinned.

**Anchor.** One diff can edit both the library and every generated copy, so parity alone is consistency. Integrity comes from the review boundary: `operator-script.sh` is a shipped plugin file, and the regeneration-parity test plus the `## Merge Danger` blast-radius field put any library edit in front of a reviewer rather than letting it ride inside a generated artefact.

### Guard 3 — the library is the only secret-writing path, and it writes safely

**Property.** No code path in the library or in any script sourcing it writes a secret to process argv, to a file more permissive than 0600, or to stdout; and an upsert of key `K` never removes a different key that merely starts with `K`.

**Assembly.** The chokepoint is the library's four write helpers (secret-to-GitHub, variable-to-GitHub, env upsert, summary printer) plus a repo-wide scan of every script that sources the library, discovered by `git grep -l` on the source line rather than by a name list. `hr-write-boundary-sentinel-sweep-all-write-sites` applies, so the scan covers every write site in the touched scripts, not only the new template.

**Mutation matrix.** Each row MUST drive the guard RED.

| # | Mutation (MUST drive RED) | Why |
|---|---|---|
| 1 | Change the GitHub-secret helper to pass the value with `--body "$VALUE"` on argv | Puts the value in `/proc/<pid>/cmdline`; the single highest-value assertion in this contract |
| 2 | Move the `chmod 600` from **after** the `mv` to **before** it | `mv` replaces the inode and its mode, so chmod-before leaves a world-readable window. A **reorder**, not a delete, because the property is about that window (`linkedin-setup.sh:448,452`) |
| 3 | Generalise the upsert filter to the prefix form `grep -v "^${KEY}"` | Upserting `X_API_KEY` then asserting `X_API_KEY_SECRET` survived is exactly the bug a generalised `linkedin-setup.sh:444` prefix filter introduces |
| 4 | Add a stage line that prints a registered secret for progress | The scrub trap must strip every registered value from output; a registry covering only the helpers is incomplete |
| 5 | Merge the variable helper into the secret helper "for symmetry" | Argv is *correct* for a login (`provision-operator-digest-repo.sh:84-86,93-94`); the guard must reject a merge that would let a secret take that path, so the variable helper must refuse secret-shaped names |
| 6 | Make the sourcing-script scan return zero files (**own-dispatch row**) | — |

**Harness rows.** (a) Point the scan at an empty fixture directory and assert the suite reddens rather than reporting "0 violations". (b) Must-PASS non-canonical: a script writing a **non**-secret on argv must pass, so the guard is a secret-path rule rather than a blanket argv ban.

**Anchor.** `stat -c %a` and a `ps`-visible argv check are properties of the produced artefact, observed independently of the code that claims to set them — the guard reads the file and the process, not the intent.

### Guard 4 — every prompt has a total non-interactive path

**Property.** For every interactive prompt in the library and in every script sourcing it there exists a named environment variable that skips it; and with stdin closed and that variable unset, the script exits **64** naming the missing variable, without blocking.

**Assembly.** The chokepoint is the library's prompt helpers plus a repo-wide scan for bare `read` forms in scripts that source the library. Census with an unclassified bucket: a `read` the scan cannot associate with a named skip variable reddens.

**Mutation matrix.** Each row MUST drive the guard RED.

| # | Mutation (MUST drive RED) | Why |
|---|---|---|
| 1 | Add a prompt with no corresponding skip variable | The property is universal over prompts, not over the ones we remembered |
| 2 | Change the no-TTY exit from 64 to 1, matching today's mute `provision-hetzner.sh:113-114` behaviour | The contract is "exit 64 **naming the variable**"; an unattributed exit 1 is the state being fixed |
| 3 | Move the TTY check to **after** the read (**reorder**, not delete) | The property is about the instant before the read. A delete-only battery goes green while the script still hangs, because a case that observes only after the function returns can never see the hang |
| 4 | Add a **second** prompt after a compliant first, with no skip variable | The check must not stop at the first prompt |
| 5 | Make the prompt scan return zero prompts (**own-dispatch row**) | — |

**Harness rows.** (a) Remove the `timeout` wrapper from the no-TTY case and assert the suite can still fail rather than hanging the runner. (b) Must-PASS non-canonical: a prompt whose skip variable is set must proceed silently and exit 0, proving the guard does not reject the automated path it exists to protect.

### Guard 5 — the refactor cannot silently drop a script out of the credential linter's scope

**Property.** Every script that acquires a credential keeps its xtrace-refusal and TLS-strip prologue **above** its `source` line, and remains in scope for `scripts/lint-shell-trace-credential-refusal.py`.

**Assembly.** Two chokepoints, and naming both is the point. (1) `PROLOGUE_MAX_CMDS = 0` at `:142-143`, whose `PROLOGUE_ALLOWED` admits only `set` / `shopt` / `readonly -<flag>` — so a `source` line is itself a counted command and the prologue must be **duplicated above** it, never moved into the library. (2) The scope predicate `SIGNAL_EXPANSION` at `:74-76`, which is **name-shaped**: it requires a `<PREFIX>_TOKEN|KEY|SECRET|PASSWORD|PAT` variable. That is the only reason `provision-doppler.sh` is in scope at all; `provision-cloudflare.sh:225` spells a bare `$TOKEN` and is not. Note also that `EXCLUDE_PATTERNS` at `:145-150` excludes `^scripts/lib/` **repo-root-anchored**, so a library under `plugins/soleur/scripts/lib/` is scanned and must satisfy the rules itself.

**Mutation matrix.** Each row MUST drive the guard RED.

| # | Mutation (MUST drive RED) | Why |
|---|---|---|
| 1 | Rename the library's hidden-entry output variable to a generic `value` / `token` | The trap: `provision-doppler.sh` drops out of the linter's scope and **the linter goes green over a file that just lost its protection**. Green-on-broken is worse than red |
| 2 | Move the xtrace refusal below the `source` line | `PROLOGUE_MAX_CMDS = 0` means the `source` line alone breaks Rule A |
| 3 | Delete the `CURL_CA_BUNDLE` unset from the prologue of a script that later makes a credentialed `curl` | The concrete MITM path at `provision-doppler.sh:260-263` |
| 4 | Have the library set `BASH_ENV` | Rule B at `:125-128` bans it, and re-exec of a generated script is exactly when someone reaches for it |
| 5 | Make the scope-membership assertion enumerate a hardcoded file list (**own-dispatch row**) | It must be derived from the linter's own predicate, or it certifies itself |

**Harness rows.** (a) Assert the guard fails when the linter is absent, rather than skipping green. (b) Must-PASS non-canonical: a script that sources the library but acquires **no** credential must pass without a prologue — the rule is scoped to credential acquisition.

**Anchor.** Membership is checked against `scripts/lint-shell-trace-credential-refusal.baseline.txt`, an independently reviewed registry, and against the linter's live predicate — not against a list this PR also edits. A `>= N` floor would survive any substitution keeping N, so **set identity** is asserted, not a count.

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/scripts/lib/operator-script.sh` | The shared library. Home and name per D3 (ADR-178 §1). Line 1 is `# shellcheck shell=bash`; header states sourcing preconditions and names every call site, per `apps/cla-evidence/scripts/_cf-admin-token.sh:1-19`. Carries the attribution comment. |
| `plugins/soleur/test/operator-script.test.sh` | The library's suite. Path follows `plugins/soleur/test/session-state.test.sh:2,10`, already registered by `scripts/test-all.sh:77` — **no `SUITE_GLOBS` edit**. Hosts Guards 3 and 4. |
| `plugins/soleur/skills/operator-bootstrap/SKILL.md` | The generator skill. Process adapted from the peer (scope → map each journey → author stages → verify and hand off); carries the attribution comment. |
| `plugins/soleur/skills/operator-bootstrap/template.sh` | The emitted template: the library region, the `STAGES` marker, one example stage, and the generated-file header marker Guard 2 discovers. |
| `plugins/soleur/skills/operator-bootstrap/scripts/verify-bootstrap-run.sh` | The discoverability probe. `--self-test` asserts the library's invariants against synthesized fixtures; `--ledger <path> --last` reads a run ledger. |
| `plugins/soleur/skills/operator-bootstrap/test/regeneration-parity.test.sh` | Guard 2. Glob `plugins/soleur/skills/*/test/*.test.sh` is registered at `scripts/test-all.sh:79`. |
| `plugins/soleur/skills/operator-bootstrap/test/predecessor-wiring.test.sh` | The anti-orphan guard: asserts `ship/SKILL.md` names `operator-bootstrap` at the point the operator step is generated, and that `commands/help.md` lists both new skills. This is what makes "a skill nothing invokes is an orphan" machine-checked. |
| `plugins/soleur/skills/operator-rephrase/SKILL.md` | The re-pitch skill. Cites `operator-digest/SKILL.md` §Register rather than restating it; carries the attribution comment. |
| `plugins/soleur/skills/brainstorm-techniques/references/phase-boundaries.md` | The ordered five-option tree body, pointed at by the new AGENTS rule. Home follows the `decision-principles.md` precedent in the same directory (the reference an AGENTS-level decision rule points at). Carries the attribution comment. |
| `plugins/soleur/skills/provision-cloudflare/test/provision-cloudflare-characterization.test.sh` | Golden `--dry-run` stdout, byte-for-byte. Measured offline-capable. |
| `plugins/soleur/skills/provision-doppler/test/provision-doppler-characterization.test.sh` | Golden `--dry-run` stdout. Measured offline-capable (its one `doppler projects` call at `:107` is `2>/dev/null` inside an `if` and is failure-tolerant). |
| `plugins/soleur/skills/provision-github/test/provision-github-characterization.test.sh` | Golden `--dry-run` stdout, **after** the hoist below makes that path offline. |
| `plugins/soleur/skills/provision-hetzner/test/provision-hetzner-characterization.test.sh` | Golden `--dry-run` stdout, with an `hcloud` stub on `PATH` to pass the `command -v` gate at `:59`. |
| `plugins/soleur/skills/provision-cloudflare/test/fixture/tenant-dpa-register.md` (and siblings) | Synthesized fixture register. **Required:** the DPA gate runs *before* the `--dry-run` branch in all four (`cloudflare:77-78`, `doppler:102-103`, `github:80-81`, `hetzner:65-66`), and the live register at `knowledge-base/legal/tenant-dpa-register.md:29` is `_(none yet)_`, so every script exits 3 on any slug without one. Column 8 is `Status` and must read `dpa-signed` or `provisioning-in-progress`. Synthesized only, per `cq-test-fixtures-synthesized-only`. |
| `knowledge-base/engineering/architecture/decisions/ADR-226-generated-operator-scripts-non-interactive-by-default.md` | Per D14. Provisional ordinal; re-derived before merge. |
| `knowledge-base/project/specs/feat-one-shot-8287-operator-bootstrap/spec.md` | Spec artifact. |
| `knowledge-base/project/specs/feat-one-shot-8287-operator-bootstrap/tasks.md` | Task breakdown. |
| `knowledge-base/project/specs/feat-one-shot-8287-operator-bootstrap/decision-challenges.md` | Three recorded challenges to the issue's stated direction: the `operator-rephrase` rename (D5), the ASD-STE100 narrowing (D13), and the scope reduction of the four-script refactor to one (D11). `ship` Phase 6 renders these and files one `action-required` issue. |

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/skills/ship/SKILL.md` | (a) Phase 6 body template at `:1773` and `:1876` gains the `## Merge Danger` section per D8, quoting `deployment-verification-agent`'s rollback line; (b) Phase 5.5 gains the D9 hold for `one-way` or blast radius ∈ {`prod-data`, `money`}; (c) the point where an operator step is generated names `soleur:operator-bootstrap` — the predecessor wiring the contract requires. Placement must not perturb the `Filed:` parse (`:1790`). |
| `plugins/soleur/commands/help.md` | Replace the flat `SKILLS: [N] skills` / `[List all skills found…]` at `:73-74` with prefix-family grouping, in **all three** harness blocks (Claude, Devin, Grok) — they are separate literal blocks and editing one leaves two stale. Add a "start here" line and name both new skills. |
| `AGENTS.rules.md` | (a) One **new** Communication rule: the ordered phase-boundary tree, first-yes-wins, Continue ruled out first, `/compact` last, cross-referencing `cm-when-proposing-to-clear-context-or`, `wg-end-of-work-emit-resume-prompt`, `cm-delegate-verbose-exploration-3-file`, and pointing at the new reference file. (b) Amend `hr-multi-step-post-merge-bootstrap-script` (292 bytes today) and `hr-ship-message-no-operator-checklist` (361 bytes) to name `soleur:operator-bootstrap` as the skill that now delivers them — **body amendments only**, ids untouched per `cq-rule-ids-are-immutable`, trimming from `**Why:**` narrative if needed per the byte-budget learning. |
| `AGENTS.md` | One new Communication index pointer for the new rule id. `lint_union` couples pointer↔body 1:1. |
| `plugins/soleur/test/components.test.ts` | `SKILL_DESCRIPTION_WORD_BUDGET` at `:21` bumped by the measured delta (estimated 2442 → 2496), with the rationale appended in the established form. |
| `plugins/soleur/skills/eval-harness/enums/go-routes.json` | Add `"drain-prs"` (D4). 8 → 9 tokens. |
| `plugins/soleur/skills/eval-harness/test/parse-label.test.sh` | The literal `8` at `:111` and `:113` becomes `9`. |
| `plugins/soleur/skills/eval-harness/tasks/go-routing.jsonl` | One golden row with `golden_label: "drain-prs"`. 8 → 9 rows. |
| `plugins/soleur/test/go-routing-golden-path.test.ts` | Guard 1 — the census. The file already loads `GO_ENUM` (`:34`) and `GO_SKILL_ROUTES` (`:10`). |
| `plugins/soleur/skills/provision-github/scripts/provision-github.sh` | **Hoist the `if $DRY_RUN` branch at `:188` above the network calls** at `:73`, `:85`, `:93-94`, `:100-101`, or emit unresolved placeholders on the dry-run path. Without this the largest of the four scripts has no offline baseline and the refactor proceeds blind. |
| `plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh` | Refactor onto the library (the one proving consumer, D11). The `read -rs` at `:123` **stays in this file** per D12. The prologue is duplicated **above** the `source` line per Guard 5. |
| `plugins/soleur/skills/provision-{cloudflare,doppler,github,hetzner}/SKILL.md` | Back-reference `operator-bootstrap`, mirroring how the `cron-list` commit updated `flag-create`, `flag-set-role`, `schedule` and `trigger-cron`. |
| `plugins/soleur/skills/operator-digest/SKILL.md` | One line naming `operator-rephrase` as the in-the-moment sibling of the weekly digest — the named predecessor that keeps it from being an orphan. |
| `plugins/soleur/skills/skill-creator/references/skill-structure.md` | The `<naming_conventions>` opening statement corrected to `<noun|domain>-<verb>` prefix-grouping with the shipped evidence (D7). Minimal, to avoid colliding with #8290's B6. |
| `plugins/soleur/NOTICE` | A new MIT entry for `mattpocock/skills`: upstream URL, "Used in:", "Portions adopted:", full licence text — the shape the three existing entries use. |
| `plugins/soleur/docs/_data/skills.js` | Two `SKILL_CATEGORIES` entries (the object opens at `:12`; `operator-digest` sits at `:31`). |
| `plugins/soleur/.claude-plugin/plugin.json` | Description counts, via `soleur:release-docs`. |
| `README.md`, `plugins/soleur/README.md` | Counts via `bash scripts/sync-readme-counts.sh`. `README.md:14` currently reads **98 skills**; it becomes 100. |
| `CHANGELOG.md` | Entry, via `soleur:release-docs`. |

**Not edited, deliberately:** `plugins/soleur/commands/go.md` (D4, D10 — this is what keeps the eval gate from firing, and it is asserted by a byte-identity check, not claimed) and `plugins/soleur/lib/workflow-fidelity.ts` (neither new skill participates in the lifecycle pipeline: `operator-bootstrap` is a leaf invoked conditionally by `ship`, `operator-rephrase` is a conversational corrective with no successor. The anti-orphan property is bought instead by `predecessor-wiring.test.sh`, which asserts the invoker names it — a stronger check than membership in a list nothing reads for these two). Both non-edits are stated explicitly in the PR body, with the named invoker, exactly as the operator contract requires.

## Implementation Phases

### Phase 0 — Preconditions (no code)

1. Confirm `plugins/soleur/skills/flag-bootstrap/` holds only `SETUP.md` and is not a live skill, so `operator-bootstrap` does not read as a `*-bootstrap` family that is not one.
2. Re-measure the skill-description budget with the test's own path and fix the bump to the measured delta.
3. Re-derive the free ADR ordinal across every `origin/*` ref, not just `main`.
4. Read `scripts/lint-shell-trace-credential-refusal.py` `:74-76`, `:125-128`, `:142-150` in full before touching any prologue.
5. Confirm `shellcheck` availability; if absent, the suites use `bash -n` and say so rather than prescribing a tool that is not installed.

### Phase 1 — Characterization first (RED before any refactor)

Write the four `provision-*` characterization suites and land them **green against today's unmodified scripts**. This is the safety net, and it is the phase that must not be skipped.

- Each suite runs with `cwd` **outside the repository**, because three of the four write `provisioning/…` relative to `$PWD` and an in-worktree run registers as a live-repo write against `scripts/lib/repo-write-boundary.sh`.
- Each supplies the synthesized DPA fixture register.
- Golden stdout is pinned byte-for-byte, **including** the duplicate teardown that a successful `--dry-run` emits (its own `--- Teardown ---` section followed by the EXIT trap's `=== Teardown commands ===`). That duplication is current behaviour and must survive.
- Also pinned: that `--help` and bad-argument exits print **no** teardown block, while DPA-gate exits (rc 3) do — because the trap is installed *below* argument validation in all four (`cloudflare:66` vs `:29-46`; `doppler:90` vs `:53-70`; `github:69` vs `:29-46`; `hetzner:55` vs `:25-30`). A library that installs its trap at `source` time would make every usage error emit a teardown banner.

The `provision-github.sh` dry-run hoist lands in this phase, because its suite cannot exist without it.

### Phase 2 — The library, test-first

Write `plugins/soleur/test/operator-script.test.sh` **before** `operator-script.sh`, driving Guards 3 and 4 red first. Then extract the library: stage progress, preflight, closing summary from `apps/cla-evidence/infra/bootstrap.sh`; the `.env` upsert from `linkedin-setup.sh:443-452` **corrected to exact-key matching**; the stdin-only GitHub secret write and the separate argv variable write from `provision-operator-digest-repo.sh:69-96`; the xtrace/TLS surround from `provision-doppler.sh:14-27`; and the additive `open_url` from `linkedin-setup.sh:322-333` **plus the new WSL arm** (`git grep wslview` returns nothing today).

### Phase 3 — `operator-bootstrap`

`SKILL.md`, `template.sh`, `verify-bootstrap-run.sh`, Guard 2's regeneration-parity suite, and the predecessor-wiring suite. Attribution comments land with the files that take prose.

### Phase 4 — The proving consumer

Refactor `provision-hetzner.sh` onto the library, with the Phase 1 golden as the gate: `--dry-run` stdout must be **byte-identical** before and after. `read -rs` stays in the file (D12); the prologue is duplicated above the `source` line (Guard 5).

### Phase 5 — `operator-rephrase` and the discoverability half

The skill; the `help.md` skill grouping in all three harness blocks; the `operator-digest` back-reference.

### Phase 6 — Rules, routing parity, and the naming correction

The new Communication rule plus its reference file and index pointer; the two rule-body amendments; Guard 1 and the `drain-prs` enum fix; the `skill-structure.md` correction. Re-run `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` after every rules edit.

### Phase 7 — Ship-side changes

`ship/SKILL.md`: the `## Merge Danger` section, the Phase 5.5 hold, and the `operator-bootstrap` invocation.

### Phase 8 — Manifest, docs, ADR, and evidence

ADR-226; `soleur:release-docs`; the `NOTICE` entry and the `hr-third-party-content-grep-on-undertaking` diff grep; the three eval-gate evidence outputs; a comment on #8289 adding the `kb-glossary` scope line; and the filed follow-up for the three deferred provision refactors.

## Acceptance Criteria

### Pre-merge (PR)

Each criterion names the command that decides it. Where a criterion claims a CI gate is green, it runs **that gate's own invocation**, never a hand-enumerated reconstruction of its inputs.

1. **Full battery green.** `bash scripts/test-all.sh` exits 0.
2. **No orphan suite.** `bash scripts/lint-orphan-test-suites.sh` reports `0 orphaned`, and `git diff origin/main -- scripts/test-all.sh` is **empty** — the new suites land on already-registered globs (D3).
3. **Library placement.** `plugins/soleur/scripts/lib/operator-script.sh` exists, its line 1 is `# shellcheck shell=bash`, and `bash -n` on it exits 0. (`shellcheck` is **not installed** on this host — measured, `command -v shellcheck` is empty — so `bash -n` is the syntax gate and no suite prescribes a tool that is absent.)
4. **Characterization goldens hold.** All four `provision-*` characterization suites pass, each run with `cwd` outside the repository, and `bash scripts/test-all.sh` reports no live-repo write.
5. **Byte-identical refactor.** The `provision-hetzner.sh` `--dry-run` golden captured in Phase 1 is byte-identical after the Phase 4 refactor.
6. **`read -rs` stays put.** `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` passes, and its Test 24 required set still contains `skills/provision-hetzner/scripts/provision-hetzner.sh`.
7. **Credential linter unchanged in scope.** `python3 scripts/lint-shell-trace-credential-refusal.py` exits 0, and the set of in-scope files is **identical** to `scripts/lint-shell-trace-credential-refusal.baseline.txt` — set identity, not a count (Guard 5 anchor).
8. **Guard 1 census.** `bun test plugins/soleur/test/go-routing-golden-path.test.ts` passes, and `jq 'length' plugins/soleur/skills/eval-harness/enums/go-routes.json` returns **9**, equal to the number of data rows parsed from the `go.md` gated block.
9. **`go.md` is untouched.** `git diff origin/main -- plugins/soleur/commands/go.md` produces **no output**.
10. **Eval-harness verdict attached, at zero API cost.** `node plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs --check plugins/soleur/commands/go.md` prints `gated: true, target: go-routing`, confirming the file is a gated source. AC9 is what proves the *block* is unchanged; `--check` alone cannot, because it answers a different question. (The `drain-prs` enum and golden-task edits sit **outside** the gated block, so the gate correctly no-ops on them; Guard 1 is the compensating control and the PR body says so rather than letting a green gate imply coverage it does not provide.) **R1:** an earlier draft also pasted a real-run no-op verdict into the PR body; cut as ceremony — it restates AC9 with two more commands.
11. **Skill-description budget.** `bun test plugins/soleur/test/components.test.ts` passes, and the bump recorded at `:21` equals the **measured** delta, not the estimate.
12. **AGENTS budget.** `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` prints `[OK]` with `B_ALWAYS` under 46000. The `2>&1` is load-bearing: WARN and REJECT print to stderr.
13. **Rule ids immutable, pointer coupled.** `python3 scripts/lint-rule-ids.py` passes; the two amended rules keep their ids; the one new rule has exactly one `AGENTS.md` pointer.
14. **Anti-orphan.** `bash plugins/soleur/skills/operator-bootstrap/test/predecessor-wiring.test.sh` passes: `ship/SKILL.md` names `soleur:operator-bootstrap`, `operator-digest/SKILL.md` names `soleur:operator-rephrase`, and `commands/help.md` names both.
15. **help.md edited in all three harness blocks.** `grep -c 'SKILLS:' plugins/soleur/commands/help.md` returns 3, and none of the three is followed by the ungrouped `[List all skills found with brief descriptions]` line.
16. **Merge Danger renders and clears the gate.** The PR body contains a `## Merge Danger` heading with all three fields populated; `.claude/hooks/ship-operator-step-gate.sh` does not block `gh pr ready`; and **no bullet** inside that section leads with a Group-A/B/C/D token. The `Filed:` line still parses.
17. **Merge Danger is derived, not invented.** The `**Undo:**` line quotes `deployment-verification-agent`'s rollback output, or reads `none produced` when review ran degraded.
18. **Docs counts honest.** `bash scripts/sync-readme-counts.sh` leaves no diff, `README.md:14` reads **100 skills**, `plugin.json` parses under `jq .`, and `npx @11ty/eleventy` builds with the component-card count matching.
19. **C4 parity.** `bash plugins/soleur/test/c4-count-parity.test.sh` exits 0 — this backs the "no C4 impact" conclusion mechanically, because the actor/system rubric does not reach the derived cardinalities `model.c4` embeds.
20. **ADR landed.** `ADR-226-*.md` exists with `## Decision` covering the seven points in D14 and `## Alternatives Considered` covering A–E; the ordinal was re-derived across every `origin/*` ref immediately before merge.
21. **Attribution complete.** Every file taking peer prose carries the required comment; `plugins/soleur/NOTICE` has the `mattpocock/skills` entry with full MIT text; and per `hr-third-party-content-grep-on-undertaking` the diff was grepped for the third party's content before PR-ready.
22. **Deferrals tracked.** The three deferred provision refactors have one filed issue with re-evaluation criteria, and its number appears on the `Filed:` line.
23. **Guard batteries executed.** Every mutation row in all five Guard Contract matrices was applied and observed RED, and every harness row behaved as specified. **R2:** the PR body carries a one-line-per-guard summary (`Guard N: k/k rows RED, h/h harness rows as specified`), not a transcription of every observation — the observations live in the suites, and the PR body is not a surface anyone reads for them.

### Post-merge

24. `soleur:postmerge` confirms the plugin CI battery is green on `main` and no docs build regressed.
25. A comment on **#8289** adds the `kb-glossary` scope line so `operator-rephrase` gains its vocabulary source in bundle 3 — a forward dependency filed, not a backward stub.

## Domain Review

**Domains relevant:** Engineering, Product, Operations.

### Engineering

**Status:** reviewed
**Assessment:** Ruled on five questions and corrected two plan decisions. (1) There is **no** rule collision — `hr-multi-step-post-merge-bootstrap-script` governs the artifact a ship emits, not all repo bash; the correct shape is a closed set of **two** carve-outs, because a credential-entry-only carve-out would delete five acknowledgement gates mandated by `hr-menu-option-ack-not-prod-write-auth`. The real deliverable is the **total non-interactive path** with exit 64 naming the missing variable. (2) Placement is already settled by ADR-178 §1; the `_*.sh` prefix and the name `wizard-lib.sh` are both rejected; the test path is free via the `session-state.test.sh` precedent, needing **no** `SUITE_GLOBS` edit. (3) Found an unmentioned blocker: `incident/test/redact-sentinel.test.sh:1206-1210` pins `provision-hetzner.sh` for its `read -rs`, so the library must not absorb that call site. Recommended splitting the four-script refactor out; this plan reduces it to one proving consumer instead. (4) One ADR, extending ADR-178, covering the generated-artifact contract rather than the library's existence. (5) Layer 7 `cli-stdout-artifact`, where a stdout-only citation is an explicit P1 rejection — hence the durable run ledger — and Sentry/Better Stack are deliberately not wired because routing a self-hosted run's output to Soleur infrastructure is a data-controller event. Also flagged the zero-headroom description budget as a CI blocker before any of the five questions.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** cpo
**Skipped specialists:** none — the mechanical UI-surface override does not fire. No path in `## Files to Create` or `## Files to Edit` matches the UI-surface glob set (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or the shared term list). The only user-facing artefacts are terminal text and a PR body, so no `.pen` wireframe is required and `wg-ui-feature-requires-pen-wireframe` does not fire.
**Pencil available:** N/A (no UI surface)

#### Findings

Reshaped three of the four scope items. (1) **B9**: a bare one-word `Door:` reproduces the documented ADR-119 defect — a label with no mechanism attached, which the ADR itself says would make an operator refuse a rollback they should take. Corrected to **Undo-first**, derived from `deployment-verification-agent` rather than judged independently, so the pipeline does not carry two uncorrelated reversibility claims. (2) **B9 delivery**: the premise "the founder reads this before approving a merge" is false on the majority path, since merge is review-gated (`wg-verified-work-ships-without-asking`, `wg-after-marking-a-pr-ready-run-gh-pr-merge`). The verdict is therefore either silent or a **hold** on the existing Phase 5.5 gate — never a new channel, because per-PR `action-required` filing would spend the credibility of the channel `operator-digest` depends on. (3) **B12**: `help.md` already groups agents but dumps skills flat at `:73-74`; that is the real founder-facing gap, and fixing it is the payoff of the naming convention. The phase-boundary tree is agent-facing and belongs in `AGENTS.rules.md`, not in either command file. Also corrected: `go.md:183` is the lifecycle handoff chain, not a context-boundary option. (4) **G5**: renamed to `operator-rephrase`; register cited rather than restated; the marketing glossary disqualified three ways; the ASD-STE100 conformance claim narrowed to an influence citation because nothing could check it. Confirmed the `single-user incident` threshold and supplied the five concrete exposure vectors now in `## User-Brand Impact`. Noted a capability gap tracked elsewhere: nothing scans a **generated** artifact (`skill-security-scan` scans skill files) — roadmap row 4.11 / #2719. Named, not expanded into this bundle. Also corrected a path in the briefing: the live brand guide is `knowledge-base/marketing/brand-guide.md`.

### Operations

**Status:** reviewed
**Assessment:** Ran eight live probes rather than inferring. The DPA gate precedes the `--dry-run` branch in all four scripts and the live register is empty, so every script exits 3 without a fixture register — this is why a synthesized fixture is a *prerequisite*, not a nicety. `provision-github.sh --dry-run` is **not** offline (four network calls execute before the dry-run branch); making it offline is the one item Operations would block PR-ready on, because otherwise the largest script is refactored blind. The trap sits below argument validation in all four, and the EXIT trap fires on the dry-run path too, so the duplicate teardown is part of the golden output. On credentials: `PROLOGUE_MAX_CMDS = 0` means a `source` line is itself a counted command, so the prologue must be duplicated above it; and the linter's scope predicate is **name-shaped**, so renaming the library's secret variable to something generic would drop `provision-doppler.sh` out of scope and turn the gate green over a file that just lost its protection — now Guard 5 mutation row 1. Also: `mv` replaces the inode and its mode, so `chmod 600` must follow the `mv`; `.gitignore:55` is a bare `.env` pattern that does **not** match `.env.<slug>`, so the library must write a file named exactly `.env` under `provisioning/<slug>/`; and characterization suites must run with `cwd` outside the repo or they register as a live-repo write. No expense or vendor impact: all four vendors are already carried in the ledger and no tier, seat or account changes.

## Test Scenarios

Written as *mutation → guard reddens*, not as *command → terminal output*. The Guard Contract matrices above are the primary battery; these are the end-to-end scenarios that sit around them.

| # | Scenario | Expected |
|---|---|---|
| T1 | Run a generated script with stdin closed and every skip variable set | Exits 0, writes the full ledger, prompts nothing |
| T2 | Run a generated script with stdin closed and one skip variable unset | Exits **64**, names the missing variable, emits `SOLEUR_BOOTSTRAP_INPUT_REQUIRED`, does **not** block (asserted under `timeout`) |
| T3 | Run a generated script with the library file removed | Emits `SOLEUR_BOOTSTRAP_LIB_MISSING` and exits hard — never degrades to a stub |
| T4 | Run a generated script under `bash -x` | Refuses with exit 78, marker on **stdout** |
| T5 | Upsert `X_API_KEY`, then read the `.env` | `X_API_KEY_SECRET` survives; file mode is `600`; the mode is `600` at every instant after the first write, not only at the end |
| T6 | Interrupt a generated script between stages, then re-run it | Second run is idempotent; the ledger shows the first run incomplete and `verify-bootstrap-run.sh --last` exits non-zero on it |
| T7 | `provision-hetzner.sh --dry-run` before and after the refactor | Byte-identical stdout, including the duplicate teardown |
| T8 | `provision-hetzner.sh --help` and a bad-argument invocation | No teardown block, exit 1 — the trap-below-validation behaviour is preserved |
| T9 | `provision-hetzner.sh` with a slug absent from the fixture DPA register | Exit 3, **with** the teardown block |
| T10 | `verify-bootstrap-run.sh --self-test` on a machine with no network, no credentials and no prior run | `12/12 invariants OK`, exit 0 |
| T11 | Generated script writes a secret to GitHub while `ps` samples its argv | The value never appears in `/proc/<pid>/cmdline` |
| T12 | A `## Merge Danger` section whose bullets lead with a deny token | `ship-operator-step-gate.sh` blocks — proving the gate is live and the section's safety is a property of its content, not of the heading alone |

## Risks & Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| The refactor drops a script out of the credential linter's name-shaped scope, turning the gate green over a file that just lost its protection | Medium — the natural instinct when extracting a helper is to rename its output variable to something generic | Guard 5 mutation row 1 drives exactly this; AC7 asserts **set identity** against the baseline, not a count |
| A generic library trap installed at `source` time changes usage-error output across all four scripts | Medium | Phase 1 goldens pin that `--help` and bad-argument exits print no teardown while DPA-gate exits do; T8 and T9 |
| The `.env` upsert generalises `linkedin-setup.sh`'s prefix filter and silently deletes an adjacent key | Medium-high — the source it is extracted from has this shape, and it is correct only for a fixed key block | Guard 3 row 3 and T5 |
| `chmod` lands before the `mv` and leaves a world-readable window | Medium | Guard 3 row 2 is a **reorder**, not a delete, because the property is about the window |
| `provision-github.sh` is refactored blind because its dry-run path is not offline | Would have been high | Descoped — it is not refactored in this PR — and the hoist lands anyway so the baseline exists for the follow-up |
| The description-budget bump is wrong because the final wording drifts from the estimate | Medium | AC11 requires the bump to equal the **measured** delta; Phase 0 step 2 re-measures |
| The ADR ordinal collides — ADR-225 is already claimed on a pushed branch and `main` moves under a long session | Medium | Re-derived across all `origin/*` refs immediately before merge; a renumber sweeps the plan, tasks and any AC naming the ordinal in the same edit |
| `#8290` edits `skill-structure.md` concurrently and conflicts with D7 | Medium | D7 is deliberately minimal — the opening statement only — to keep the conflict surface to a few lines |
| The Merge Danger hold blocks a merge the founder wanted | Low-medium | The hold fires only on `one-way` or blast radius ∈ {`prod-data`, `money`}; it reuses the existing Phase 5.5 machinery rather than adding a new stop |
| A generated `bootstrap.sh` is not scanned by any security gate | Low, but unmitigated here | Named as a known gap owned by roadmap row 4.11 / #2719; deliberately **not** expanded into this bundle |
| Playwright MCP failed to connect in this planning session | Certain, already observed | No plan step depends on it. Where `hr-never-label-any-step-as-manual-without` requires a Playwright attempt before calling a browser step operator-only, `/work` must run that attempt itself and must not inherit an a-priori "operator-only" assertion from this plan |

## Alternatives Considered

| Alternative | Why not |
|---|---|
| Port `template.sh` verbatim as the issue proposes | Would create a sixth copy of an `.env` upsert already duplicated four times, and a second stage-progress implementation beside `apps/cla-evidence/infra/bootstrap.sh`. Extraction buys the same property against code already exercised |
| Interactive-first wizard, as the peer ships it | Hangs with no TTY under `one-shot` and CI, and its browser step conflicts with `hr-never-label-any-step-as-manual-without` absent a Playwright attempt |
| Non-interactive only, zero carve-outs | Would delete five acknowledgement gates that `hr-menu-option-ack-not-prod-write-auth` mandates for destructive writes against shared production |
| Add `/go` routing rows for both skills | Neither is a work request; a new token widens the enum from 8, reddens two pinned literals, needs a golden task and a regenerated projection, and costs ≈144 API calls. The contract's explicit not-routable escape is the honest fit |
| Import the peer capability map into `go.md` | `help.md` already maps agents; the gap is that it dumps skills flat. A second map competes with the one that exists |
| Put the phase-boundary tree in `go.md` or `help.md` | The founder reads neither. It is agent-facing and belongs in `AGENTS.rules.md` with its body in a reference file |
| Ship the bare one-word `Door:` field | Reproduces the ADR-119 defect: a verdict nobody can check. Undo-first makes it falsifiable |
| File Merge Danger as a per-PR `action-required` issue | Would flood the channel `operator-digest` depends on, and the verdict expires at merge so a weekly digest cannot deliver it |
| Refactor all four provision scripts in this PR | Week-plus against 1041 lines with zero prior coverage and live credentials, per two independent domain assessments. Reduced to one proving consumer plus characterization tests for all four |
| Split into two or three PRs as both domain leaders recommended | A one-shot run produces one PR. Scope is reduced instead, which removes the same risk without fragmenting delivery |
| Trim two sibling skill descriptions to pay for the two new ones | Pays for this feature by degrading unrelated skills' discoverability. Every prior addition took the bump path with the baseline documented |

## Deferrals

Each gets a filed issue with re-evaluation criteria and a milestone drawn from `knowledge-base/product/roadmap.md`, per `wg-when-deferring-a-capability-create-a`. Their numbers appear on the PR's `Filed:` line.

1. **Refactor `provision-cloudflare.sh`, `provision-github.sh` and `provision-doppler.sh` onto the library**, in that order of ascending blast radius. Re-evaluation: once the characterization goldens from Phase 1 have survived one release cycle unchanged. The issue body carries the full sequencing note, including why Doppler is last (`:4-13` explains why its conditional xtrace arm is vacuous by construction, and `:21-27` is bespoke).
2. **Scanning generated artefacts.** `skill-security-scan` scans skill *files*; a generated `bootstrap.sh` is squarely its target class but outside its input. Owner is roadmap row 4.11 / #2719 — this is a **pointer**, not a new issue, and the dependency is noted on #8287 rather than expanding this bundle.
3. **The `kb-glossary` vocabulary source for `operator-rephrase`** — a comment on #8289 adding the scope line, not a stub here.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is populated with five concrete vectors and the threshold is `single-user incident`.
- **`shellcheck` is not installed on this host** (measured). No suite or AC may prescribe it; `bash -n` is the syntax gate. If a later environment has it, adding it is an improvement, not a correction.
- **The eval-gate `--check` verb answers a different question than the gate does.** `--check <file>` reports whether the *file* is a gated source, so it returns `gated: true` for `go.md` even when the edit is outside the block. The claim that matters — no gated-block change — is proven by the real-run form's documented ungateable-no-op arm plus an empty `git diff` against `origin/main`, not by `--check`.
- **The `drain-prs` enum and golden-task edits are outside the gated block, so the eval gate correctly no-ops on them.** That is not the same as "they were evaluated". Guard 1 is the compensating control and the PR body says so rather than letting a green gate imply coverage it does not provide.
- **`help.md` renders three separate harness blocks** (Claude, Devin, Grok) that each contain their own `SKILLS:` line. Editing one and leaving two stale is the modal failure; AC15 counts all three.
- **`.gitignore:55` is a bare `.env` pattern.** It matches `.env` at any depth but **not** `.env.local` or `.env.<slug>`. Anything the library writes must be named exactly `.env`, under `provisioning/<slug>/` which `.gitignore:83` already covers.
- **Characterization suites must run with `cwd` outside the repository.** Three of the four scripts write `provisioning/…` relative to `$PWD`, so an in-worktree run registers as a live-repo write against `scripts/lib/repo-write-boundary.sh` and `scripts/test-all.sh` exits 2.
- **A `source` line is a counted command** under `scripts/lint-shell-trace-credential-refusal.py`'s `PROLOGUE_MAX_CMDS = 0`. The xtrace refusal and TLS strip must be **duplicated above** it in every credential-acquiring caller — they cannot move into the library.
- **The linter's scope predicate is name-shaped.** Renaming a secret variable to something generic removes a file from scope and the gate goes green over a file that just lost its protection. Green-on-broken is worse than red.
- **`mv` replaces the inode and its mode.** A `chmod 600` written before an upsert's `mv` is a no-op on the resulting file.
- **ADR-225 is already claimed on a pushed branch.** The provisional ordinal here is ADR-226, derived across all 89 `origin/*` refs rather than `origin/main` alone, and it must be re-derived immediately before merge.
- **`plugins/soleur/skills/flag-bootstrap/` exists with no `SKILL.md`**, which is why the directory count (99) and the skill count (98) differ. Confirm it is inert before `operator-bootstrap` lands beside it.

## Plan Review Revisions (R1–R24)

**These revisions supersede the sections above where they conflict.** Panel: DHH, code-simplicity,
architecture-strategist, spec-flow-analyzer (eng, escalated to 5 by the `single-user incident`
threshold) plus the relevance-gated named panel (cpo, cto-devex). Kieran was dispatched and its
report did not reach this session — recorded as an error, not as a pass; `deepen-plan` covers the
same correctness axis and the Kieran-class checks are re-run there.

Where the **simplification** panel (DHH, code-simplicity) and the **correctness** panel
(architecture, spec-flow, cpo, cto) fired on the *same* scope, the consolidation prefers **delete
over fix** — and in five places the deletion dissolved the correctness findings outright rather than
requiring them to be fixed.

### The three structural reversals

#### R6 — One distribution mode: the generated script **sources** the library. The inlined-library architecture is cut.

Four reviewers converged on the same contradiction from different directions, and it is a genuine
fork, not a preference: the plan specified **both** an inlined library (Guard 2 pins the region above
`STAGES` byte-identical) **and** a sourced one (D3, and `provision-hetzner.sh` doing
`source "$SCRIPT_DIR/…"`). These cannot both hold. A sourced library's line 1 is
`# shellcheck shell=bash` with no shebang; an inlined script must open `#!/usr/bin/env bash`,
`set -euo pipefail`, then the xtrace prologue above any command. The two regions differ in their
first five lines **by construction**. The tell was already in the plan's own observability block: the
failure mode `SOLEUR_BOOTSTRAP_LIB_MISSING` is *impossible* for an inlined library and is only
meaningful for a sourced one.

**Resolution: sourced.** This is a technical fork, resolved here rather than surfaced
(`hr-technical-fork-is-not-an-operator-question`). What it buys:

- Guard 2, the `STAGES` marker invariant, `regeneration-parity.test.sh` and observability failure
  mode 6 all **disappear** — not because the drift stopped mattering, but because there is no longer
  a copy to drift from.
- `SOLEUR_BOOTSTRAP_LIB_MISSING` becomes a real, reachable failure mode instead of an unreachable one.
- The contributor contract drops from ten invariants to seven, and the three that actively
  contradicted each other (the marker invariant, regeneration parity, prologue-above-`source`) reduce
  to one consistent rule.
- The library stops being copied into artifacts no guard can sweep.

Cost: a generated script needs the plugin present at run time — already true of every consumer this
plan names, and true by definition of a Soleur user. **This contradicts the issue's stated
"immutable library above a `STAGES` marker" architecture, so it is recorded as DC-4.**

#### R7 — The `## Merge Danger` block ships with **two** fields. `Door:` is cut, and the Phase 5.5 hold is deferred.

`Door:` was cut for a reason the plan itself had already written down: D8 states *"`Door` cannot be
written without `Undo`"*, which is the definition of a derived field. It maps onto neither clause of
P3 — `Undo:` answers "can it be undone", `Blast Radius:` answers "how far do effects reach".

Cutting it **dissolves two independent P0s** rather than requiring them to be fixed:

- `deployment-verification-agent` runs only when a PR touches production data, migrations, or
  record-discarding behaviour. For a plugin-only PR — **including this one** — it never runs, so
  `Undo: none produced` was the *default* case, not the degraded edge case the plan framed it as.
  With `Door:` present, that default left `Door` unconstrained (reopening the exact ADR-119 defect
  D8 exists to close) *or* forced `Door: one-way` on every docs-only PR, which fired the hold. Both
  branches were closed by the plan's own rules. With `Door:` gone, there is no unanswerable field.
- `none produced` and `none known` collapse to **one** sentinel, `none known`, removing the third
  literal AC17 introduced that the field grammar never admitted.

**The hold is deferred.** Reviewers found it had no interactive arm, no cloud arm, no headless arm
and no override token, against a cited precedent (`ship/SKILL.md:203`) that defines all three; that
it was specified in Phase 5.5 while its *input* is written in Phase 6, so it would evaluate a field
that does not yet exist; that its key (`Blast Radius`) is a free-choice string with no derivation,
no enum check and no test — re-adopting the shape `ship/SKILL.md:201` deliberately rejected when it
moved `Reviewed-Coverage` into a script-emitted git trailer; and that it plausibly fires on **this
very PR** (`provision-hetzner.sh` creates a billable server). In a repo whose premise is
`wg-verified-work-ships-without-asking`, a self-assessed field that halts autonomous delivery with
no exit is a wedge.

So: **ship the block, watch the field, earn the hold.** The deferred issue carries the activation
criterion — a measured firing rate across a stated number of PRs, plus the three arms and an override
token modelled on `ship/SKILL.md:203` — rather than a promise to revisit.

#### R8 — D2's carve-out set was wrong: there are **three** classes, and the ack class takes **no** skip variable.

This is the most serious correctness finding in the review and it inverts a safety claim.

D2 classified five prompts as carve-out 2, "per-command destructive-write acknowledgement". Read
literally, **none of the five is that.** All are *out-of-band completion attestations* — the script
pausing until a human has done something outside it (ran an apply in another terminal, created a
console token, installed a GitHub App). They authorize nothing the script is about to do. That is a
**third class**, which D2 itself said requires an ADR amendment.

The sharpest instance is in the one script this PR refactors. The plan's justification chain rests on
`provision-hetzner.sh` acknowledging its billable server. Measured: the ack (`Token created? Type
'yes'`) acknowledges *token creation*; the `read -rs` follows it; and the billable
`hcloud server create --name "$PROBE_NAME" --type cx11` comes **after both, with no acknowledgement
between them**. So if `/work` had implemented that ack as "the destructive-write ack" and — per D2's
total-non-interactive rule — given it a named skip variable, the refactored script would create a
real billable server fully unattended. That is precisely what `hr-menu-option-ack-not-prod-write-auth`
exists to prevent, introduced by the PR claiming to enforce it.

Guard 4 made it worse: its property said *every* prompt has a skip variable, which would have forced
`/work` to add one to the ack and left the guard **green over a rule violation**. An environment
variable set once is exactly the "prior approval extending to new commands" that rule forbids.

**Revised contract:**

| Class | Example | Non-interactive behaviour |
|---|---|---|
| 1 — ladder value (credential entry) | `read -rs` for a vendor token | Named skip variable; no TTY + unset ⇒ exit 64 naming the variable |
| 2 — per-command destructive-write ack | the acknowledgement that must gate `hcloud server create` | **No skip variable at all.** No TTY ⇒ exit 64 unconditionally. Automation must not be able to supply this |
| 3 — out-of-band completion barrier | `Token created? Type 'yes'`, `App installed? Type 'yes'` | Named skip variable, **and** the barrier must be followed by an independent verification of the thing attested |

Class 3's "must be followed by an independent verification" is load-bearing and was missing from the
plan entirely. It is why the existing barriers are safe to skip today: each is followed by a
`terraform output`/`curl` verify, a `doppler projects get`, or a `gh api /installation`. Guard 4
would have gone green on a barrier with a skip variable and no downstream verification.

Two consequences: `provision-hetzner.sh` needs a class-2 ack introduced before its server create (it
has none today), and `provision-github.sh`'s App-install step carries an explicit ToS consent note in
its own source, so a skip variable there is a compliance question, not just a design one — it stays
class 3 with its `gh api /installation` verification, and the ToS tension is stated in the ADR.

### Cuts — each removes a mechanism that buys no property in P1–P5

| # | Cut | Why | Panels |
|---|---|---|---|
| R9 | **Guard 1, the `drain-prs` enum fix, and the `parse-label.test.sh` / `tasks/go-routing.jsonl` edits** | Buys no P1–P5 property. Its anchor is circular for the three artifacts the PR edits and covers only the one artifact AC9 forbids touching, and its assembly omitted two of the five coupled artifacts the plan's own research enumerated — including `prompts/go-skill.txt`, which is where the live defect actually manifests | DHH, code-simplicity, architecture |
| R10 | **Guard 5 in full** | The property is already bought twice: `scripts/lint-shell-trace-credential-refusal.py` runs repo-wide with its own mutation suite (AC7), and `redact-sentinel.test.sh` Test 24's predicate is **mechanism**-keyed, so moving the prompt into the library reddens it (AC6). Its headline mutation row targets `provision-doppler.sh`, which D11 defers and which never sources the library in this PR — the row cannot be driven | code-simplicity, architecture, cto |
| R11 | **Three characterization suites (`cloudflare`, `doppler`, `github`) and their DPA fixtures** | They protect work in a follow-up issue and are deliberately aged ("survived one release cycle"). A byte-for-byte golden pinning current quirks is a maintenance liability on every unrelated PR that touches those scripts | DHH, code-simplicity, cto |
| R12 | **The `provision-github.sh` dry-run hoist** | It is not a hoist. The org and reviewer IDs are resolved by network calls above the branch and interpolated into the generated config, so moving the branch **changes the dry-run output**. The golden captured afterwards characterizes freshly-written code and cannot be compared to `origin/main` — the one script it claims to protect ends this PR with no pre-change baseline at all. It is the only unverified change in a PR built on verification | DHH, code-simplicity, cto, architecture |
| R13 | **`verify-bootstrap-run.sh --self-test`** | Duplicates `plugins/soleur/test/operator-script.test.sh` plus Guards 3 and 4, which already assert the same contract in CI with mutation matrices. Its `"12/12 invariants OK"` is a hardcoded count in an expected-output string — the frozen-list defect this plan's own guards forbid elsewhere. `--ledger --last` is kept | DHH, code-simplicity, cto |
| R14 | **`predecessor-wiring.test.sh` as a separate file** | Four string greps wearing a suite. `plugins/soleur/test/components.test.ts` already walks skills and reads `commands/help.md`; the assertions fold in, costing no new file, no registration surface and no orphan-lint entry | code-simplicity |
| R15 | **The new AGENTS Communication rule and its index pointer** | `cm-when-proposing-to-clear-context-or` is already the Communication rule about this exact boundary. **Amending its body** costs no new id, no `AGENTS.md` pointer, no `lint_union` coupling and no permanent always-loaded budget — and honours `cq-agents-md-tier-gate`'s "edit the owning artifact" branch rather than arguing around it. `references/phase-boundaries.md` is kept and the amended rule points at it | code-simplicity |
| R16 | **ADR-226 Decision points 5–7 and Alternatives C–D** | Restate Guard 2 (now cut), ADR-178 §1 (which already rejects skill-local and repo-root placement by name), and `## User-Brand Impact` | code-simplicity |

### Corrections — things that were unsatisfiable, miscounted or mis-cited

- **R17 — AC7 is rewritten; it could never have passed.** It asserted the linter's in-scope set is *identical* to `scripts/lint-shell-trace-credential-refusal.baseline.txt`. That file is the **violator/debt list** — its own header says "files that bind a live credential **without** the xtrace refusal". Measured: `1117 scanned, 76 baselined`. `provision-doppler.sh` is in scope precisely *because* it is compliant, so it is absent from the baseline. There is also no verb that emits the in-scope set (`--census` prints offenders only). AC7 becomes: **the linter exits 0, and `provision-hetzner.sh` is not newly baselined** — a non-regression assertion over the set that actually exists.
- **R18 — the refactor pulls `provision-hetzner.sh` *into* the linter's scope for the first time.** It binds its token via `read -rs` and only ever exports and unsets it, never expanding it, so the name-shaped scope predicate does not currently match. The moment the refactor passes that token to a library helper, the file enters scope with no prologue and becomes a new offender. Guard 5's property said the prologue is "**kept**"; for its only live subject it is **acquired for the first time**. This is a five-line fix once named, and it is the single most likely implementation surprise.
- **R19 — `## User-Brand Impact` claims five controls; there are four.** The section has one availability vector and four leak vectors; only the leak vectors name controls. The availability vector — the half-populated `.env` and partially-set secrets that leave the founder's repo unrecoverable — has no control named, so the "survivable by construction, not by review diligence" claim does not hold for it. Corrected to four, with the recoverability vector's mitigation named honestly as R21's work rather than as an existing above-the-marker control.
- **R20 — the `operator-rephrase` description contradicts D13 on both counts.** The measured 23-word string says "plain **controlled English**" (the term of art for the standard D13 declines to claim) "using **the project's own vocabulary**" (a source D13 says does not exist in v1). It is the one founder-visible string of the two new skills and the budget AC checks only the bump's arithmetic, never whether the sentence is true. Replaced with: *"This skill should be used when the last message did not land: say it again in short plain sentences, with no jargon, file paths or issue numbers."* (25 words). `/work` re-measures the bump against the final wording.
- **R21 — three founder-facing dead ends in the generated-script journey must be closed in the library contract.** (a) A **wrong** credential is permanent: the value is persisted before validation, and the env-var-first ladder means a re-run never re-prompts — it fails identically forever. The library needs validation before persistence and a `--reset <KEY>` path. (b) **Re-run is not idempotent** over a non-idempotent create; the plan asserted idempotence as a test expectation with no mechanism behind it. The generator's authoring rules must require each stage to open with an "already satisfied?" precondition, and that requirement belongs in `operator-bootstrap/SKILL.md`. (c) There is **no resume**: the ledger detects a partial run and the only supported action is to re-run from stage 1, into (b). A `SOLEUR_BOOTSTRAP_START_STAGE` read from the ledger closes it. **SIGINT** is also unaddressed — the founder's actual interrupt leaves a state byte-identical to a crash.
- **R22 — nothing in the plan actually generated a `bootstrap.sh`.** `ship`'s operator-step gate offers three options (file a deferred-automation issue, cite an existing one, attest an override) and **none is "generate a script"**; the predecessor guard asserted only that `ship/SKILL.md` contains the literal skill name, which is a mention test, not an invocation. The journey had no first step. Adding the fourth option to that gate is now an explicit task, and the folded-in assertion (R14) checks the invocation, not the mention. The artifact's home is also pinned to one location rather than the three the plan named.
- **R23 — `help.md` gets a *rendering rule*, not three enumerated family lists.** The existing instruction is self-maintaining ("list all skills found"); replacing it with hand-written families in three harness blocks converts one auto-updating surface into three that go stale in triplicate — the exact modal failure the plan's own Sharp Edges names, made permanent rather than one-time. The replacement is one sentence: *list all skills found, grouped by the token before the first hyphen, families ordered by size, ungrouped skills last under "Core workflow"*. It still auto-updates, still delivers the grouping payoff, and it disposes of the ~65 skills that carry no prefix — which the enumerated form left with no home.
- **R24 — smaller fixes.** ADR-226's relationship label becomes **"constrained by"** ADR-178, not "extends" — the subjects are disjoint and the only touch point is a deferral; the repo's precedent for that shape is ADR-178's own header. Guard 4 gains the **Anchor** it was missing (the `exit=64` no-TTY probe, already written in the Observability section but never attached). `provision-hetzner.sh` line citations are ~13 lines stale and are replaced with content anchors per `cq-cite-content-anchor-not-line-number`. The `closes: 8287` claim is kept **only if** the PR body restates the narrowed scope in the same sentence. Deferral 2's owner is stale by this plan's own D7 test — #2719 scopes to skill files being authored or installed, not to a generated artifact — so it is filed rather than pointed at. #8289 is milestoned `Post-MVP / Later`, so `operator-rephrase` v1 is described as the durable state, not as awaiting a glossary. The layer-7 citation states explicitly that the ledger is committed in the **founder's** repo (both candidate paths are gitignored *here*), and `discoverability_test.command` becomes `bash plugins/soleur/test/operator-script.test.sh`, which already satisfies the probe-verb gate.

### Cross-bundle sequencing note (advisory, not applied)

#8290's invocation-axis work removes user-invoked-only skill descriptions from the always-loaded
budget **entirely**, and its candidate list includes all four `provision-*` skills. That dominates
D6's +54 bump on both options the Alternatives table weighed, and both bundles edit the same constant
on the same line. #8290's B6 also resolves a markdown-vs-XML contradiction in
`skill-creator/references/skill-structure.md` — the file D7 edits, whose naming convention lives
*inside* the XML block B6 may rewrite wholesale, which defeats D7's minimality mitigation. D7 is
therefore reshaped as a **note** beside the existing patterns rather than a replacement of the
normative sentence, since a minimal edit that leaves five verb-first examples beneath a noun-first
statement makes the file contradict itself. A comment on #8290 records both couplings.

### Net effect

Guards 5 → 3. Files to create 18 → 12. Files to edit 19 → 14. Mutation rows 26 → ~14. Acceptance
criteria 23 → ~18. No property in P1–P5 is lost. Five correctness findings (the unanswerable `Door:`
field, the holdless hold, the Phase-5.5-before-Phase-6 ordering, Guard 2's unreachable population,
Guard 5's non-existent anchor) were **dissolved by cuts** rather than fixed, which is the outcome the
consolidation rule predicts when both panels fire on one scope.

### Second consolidation pass (R25–R40) — Kieran

The Kieran report reached this session after the R1–R24 block was written. It is the correctness
panel's live-verification arm and it falsifies three claims the first pass preserved. **R25 and R26
are the two that invert a decision.**

- **R25 — D12's cited mechanism is false; the conclusion survives on a different reason.** D12 said
  moving `read -rs` into the library "drops `provision-hetzner.sh` out of Test 24's set and fails
  it." Test 24's predicate is **content-keyed**, not filename-keyed
  (`incident/test/redact-sentinel.test.sh:1186`, `read -[a-z]*s ` among the alternatives), and
  `provision-hetzner.sh` matches it **twice** — the second hit is an `echo` inside the dry-run block
  that prints a `read -rs` recipe, and the comment-stripper keeps `echo` lines. Measured: delete the
  real prompt and the predicate still matches. So the prompt may move without reddening Test 24.
  **The conclusion still holds** — the prompt stays in the caller because of Guard 5's prologue rule
  and because the prompt string is the operator-facing product — but ADR-226 `## Decision` point 4
  must cite **that** reason. Enshrining the Test-24 claim would write a false constraint into a
  record later plans treat as binding. **AC6's second clause is also dropped: it asserts a hardcoded
  array in a file this PR never edits, so it cannot fail.**
- **R26 — a sourced xtrace guard buys nothing, and R6's sourced mode has an unresolved consequence.**
  `find_preamble` scans only the file's own lines, so a caller sourcing a fully-compliant library
  still exits 1 — measured against fixtures. Guard 5's duplicate-above-`source` rule is right and
  D12's "the library supplies the xtrace refusal" is wrong. Worse, and unaddressed anywhere: the
  library at `plugins/soleur/scripts/lib/operator-script.sh` is **itself in scope** (the exclusion is
  repo-root-anchored), and the "a sourced `exit` kills the parent" carve-out applies only to
  repo-root `scripts/lib/`. So if the library ever expands a `*_TOKEN`/`_KEY`/`_SECRET`-shaped name
  it must carry its own `exit 78`, which terminates its caller on `source`. **Resolution: the library
  never expands a secret-shaped variable name.** Secret values reach it as positional parameters with
  neutral local names, and every expansion of a caller-named secret stays in the caller. That keeps
  the library out of scope by construction and is now a library invariant in ADR-226.
- **R27 — three more PR-body gates, one of which `Blast Radius` arms directly.**
  `scripts/ship-incident-pir-gate.sh:191`'s `PROD_RE` matches `prod`, so **`**Blast Radius:**
  prod-data` supplies half its conjunction**; the other half is an outage past-tense token, which is
  exactly the register a reversibility narrative produces. `.claude/hooks/ship-soak-followthrough-gate.sh:268`'s
  `SOAK_RE` matches `post-deploy (soak|verif|observ)`, so an `**Undo:**` line reading "post-deploy
  verify the rollback" arms it and then demands sweeper enrollment for every `Ref #N` in the body —
  which means the plan's `### Soak Follow-Through Enrollment: Not applicable` was **asserted, never
  gated**. `.claude/hooks/pre-merge-auto-close-scan.sh:257,283` denies prose-embedded close keywords,
  so an `**Undo:**` line saying "revert the PR that closes #N" trips it. All three join the
  gate-safety constraint set, and the blast-radius enum value `prod-data` is renamed to avoid the
  bare token.
- **R28 — the Merge Danger section must sit ABOVE `## Changelog`.** `.github/workflows/reusable-release.yml:366`
  truncates release notes at the next `## ` heading after `## Changelog`. The template happens to
  place it correctly; nothing stated it as a constraint, so a later reorder would silently drop it
  from every release note. Now an explicit constraint with an AC.
- **R29 — `Filed:` is a disjunction, and the fallback template omits it.** `net-issue-flow.sh:431-438`
  counts an issue if its own body cites the PR **or** it appears in the declared list; `Filed:` is
  the only *PR-body-derived* source, not the only counted one. Separately the `gh pr create` fallback
  template omits the `Filed:` line entirely while the `gh pr edit` template has it — the plan edited
  both as if symmetric.
- **R30 — two acceptance criteria cannot fail; both are corrected.** AC15's first clause
  (`grep -c 'SKILLS:' == 3`) is **pre-satisfied today**; only the second clause carries signal, and
  R23's rendering-rule form needs a different assertion anyway. AC19 is worse: `c4-count-parity.test.sh`
  is scoped to counts hard-coded in `model.c4` edge prose (workflow check-ins, cron monitors), passes
  today, and cannot fail from a change that touches no workflow and no cron monitor — **so it cannot
  mechanically back the no-C4-impact conclusion the plan assigned it.** That conclusion rests entirely
  on the by-hand actor/system/relationship rubric, and the plan now says so instead of borrowing
  authority from a green gate with a different scope.
- **R31 — the description-budget bump has no phase and is ordered behind its consumers.** The two new
  `SKILL.md` files land in Phases 3 and 5; Phase 0 only *re-measures*; no phase bumps the constant. So
  `components.test.ts` is RED from Phase 3 through Phase 8. **The contract edit moves to Phase 0**,
  ahead of the first consumer — the same contract-before-consumer ordering the plan already applies
  in Phase 2.
- **R32 — the folded-in wiring assertions (R14) must land in the phase whose contracts they assert**,
  not in Phase 3. They assert `ship/SKILL.md` (Phase 7), `operator-digest/SKILL.md` (Phase 5) and
  `help.md` (Phase 5). They move to Phase 7, or Phase 3 declares them red-first the way Phase 2
  declares its inversion.
- **R33 — the eval-harness cost figure is understated ~2×, and the doc disagrees with the tool.**
  D4 and the Alternatives table cite "≈144 calls at `--repeat 3`", faithful to `eval-harness/SKILL.md`.
  The tool reports `estimated_api_calls: 270, repeat: 5`. Since R9 cuts the routing bundle the figure
  is no longer load-bearing, but the *doc* is wrong and a one-line correction rides along.
- **R34 — the AC10 invocation errors as written.** `--target` is mandatory, and `--candidate-file`
  must differ from the live source path. R1 already cut the real-run paste as ceremony; this records
  that it was also unrunnable, and that once corrected it is a tautology — copying an unmodified file
  to a temp path and asserting it is unchanged cannot fail.
- **R35 — "Column 8 is `Status`" would break all four characterization suites.** Status is the
  **7th visible column**; it is `awk -F'|'` field `$8` only because the leading pipe makes field 1
  empty. A fixture author reading the plan literally puts Status in the 8th visible column and every
  Phase-1 suite fails against a fixture that looks right. The fixture spec now states both.
- **R36 — the T12 deny-token fixture passes for the wrong reason as specified.** GROUP_B and GROUP_C
  are narrower than the plan described: each additionally requires a trailing action verb. A fixture
  carrying only `T+90 min` never arms the gate, so T12 would go green while proving nothing. The
  fixture must carry the trailing verb.
- **R37 — there is a divergent doc-twin of the detector.** `ship/SKILL.md:1403` carries a prose copy
  of `DETECT_RE` already narrower than the hook's (no `Operator:` colon form, no GROUP_B/C). This PR
  edits `ship/SKILL.md` heavily and never reconciles it. Either update it or mark it as a summary.
- **R38 — the orphan-suite lint is bidirectional.** It also errors on **double** coverage and on any
  registration surface matching zero suites. The plan's "must land on a registered glob or the lint
  reddens" is one-sided; a suite matching two globs is equally red.
- **R39 — line-anchor drift, swept.** Corrections: the billable create and its trap in
  `provision-hetzner.sh` are ~13 lines below the cited anchors (`:118` is an `echo`); Phase 1.5 spans
  `:138-250`, not `:138-175`; Model Dissents is at `:1769` only; the `test-all.sh` "glob matching
  nothing" comment and the registering entry are each one to two lines off, and the `lib/` precedent
  comment is about `.claude/hooks/lib/`, not `plugins/soleur/scripts/lib/` — the principle transfers,
  the citation does not; the redact-sentinel anti-vacuity block starts one line earlier than cited, on
  the line that states the property. Per `cq-cite-content-anchor-not-line-number`, `/work` replaces
  these with content anchors rather than re-deriving numbers that will drift again.
- **R40 — D13's negative assertion is already self-falsified.** The claim that
  `grep -rn "ASD-STE100\|Simplified Technical English\|controlled English"` returns zero is now false
  on this branch: this session's own `decision-challenges.md` and `tasks.md` contain the strings. The
  claim is restated as scoped to `plugins/` and to `origin/main`, which is what was actually measured.

**Panel coverage.** Seven reviewers dispatched, seven reported: DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer (eng panel, escalated to five by the threshold) plus cpo
and cto-devex (relevance-gated named panel). `ux-design-lead` and `cmo` were not activated — the
mechanical UI-surface scan over `## Files to Create` and `## Files to Edit` returns no match, and the
plan carries no market, GTM or brand-copy surface. An earlier note in the R1–R24 block recorded
Kieran as not-delivered; that was true when written and is superseded here.
