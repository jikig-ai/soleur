---
title: "refactor(skills): invocation-axis budget relief + positive-phrasing rule rewrite (eval-gated)"
date: 2026-09-21
slug: refactor-invocation-axis-budget-relief
branch: feat-one-shot-8290-invocation-axis-budget-relief
issue: 8290
closes: 8290
type: refactor
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
---

# refactor(skills): invocation-axis budget relief + positive-phrasing rule rewrite (eval-gated)

## Enhancement Summary (deepen-plan)

**Deepened on:** 2026-09-21. **Halt gates:** 4.6 pass (`aggregate pattern`). **4.7 FIRED and was
fixed**: the Files-to-Edit include `.ts`/`.cjs` code, so the prose-only Observability note was replaced
with the 5-field schema and the telemetry was emitted. 4.8 pass (no PAT shapes). 4.9 skip (no UI).
4.10 skip (no store). 4.11 pass (`lint-guard-contract.py`: 2 entries, green; the assemblies are
structural, derived rather than member lists).

**Agents in the deepen pass:**

- a verify-the-negative and post-edit self-audit sweep (standard tier);
- `soleur:engineering:review:security-sentinel`;
- `soleur:engineering:research:git-history-analyzer`;
- `soleur:engineering:review:pattern-recognition-specialist` (precedent diff).

These follow the 9-seat plan-review panel, the Phase 2.5 domain leaders (CTO, CPO, COO, CLO) and the
Step 4.5 strong-model consult.

### Key improvements

1. **Observability**: a 5-field schema. The liveness signal is the Guard 1/budget CI tests. The probe
   is `grep -c '^disable-model-invocation: true' .../flag-create/SKILL.md` → `1`, with a W0-STOP
   alternative.
2. **Precedent alignment**, with every change citing its file:line precedent:
   - floors become named constants (`LIVE_MIN_FILES` style);
   - count-equality runs against a *separate* literal pathspec list;
   - keep-pins move to their own `MUST_STAY_INVOCABLE` set rather than `ACKED_CROSS_ROOT_DUPES`,
     which is pinned to go/help/sync and asserts `user-invocable: false`;
   - the measure script takes the house `pass`/`score`/`reason` shape;
   - the verdict CLI takes the `verdict.cjs` + `eval-gate.cjs` exit-code shape;
   - the battery floor takes the exact `lint-rejected-register.test.sh:1110-1126` shape, so
     `guard-vacuity-floor` scores it FIRES.
3. **Security.** The flip is recorded as a context-budget measure, **not a security control**. The
   pre-existing agent-bypass surface is scoped into a tracked follow-up: 3 stdin-fed typed-yes prompts,
   plus `flip.sh --confirmed`, with the explicit warning that `[[ -t 0 ]]` is not the fix. The raw
   eval grid stays out of the repo. `gitleaks` gates `w0/` and the results. Probes run with
   `--disallowedTools Bash,Write,Edit` and a tmux kill trap.
4. **Contradiction removed.** The Cut List's "no committed B5 fixture test" is marked reversed,
   matching the R10 battery.

### Verified live (no drift found)

- Every cited PR, issue, ADR and peer path, all resolved.
- ADR-236 is free across every `origin/*` ref.
- The three peer blobs return 200 at `c55ee46`.
- `B_ALWAYS=42920`, which makes ADR-151's recorded figure stale by +373 B.
- The G1 and G3 scans find 0 hits today.
- `schedule`'s description already covers listing and deleting.
- The new battery auto-registers through `test-all.sh:79`.


## Overview

Bundle 4 of 5 from the mattpocock/skills peer-plugin audit. Three independent deliverables share one
theme, "write once, load less": move human-only skills off the always-loaded skill listing via the
invocation axis, test (with the eval harness, before any rewrite) whether positively-phrased rule
bodies steer better than prohibitions, and add four authoring levers to the skill-creator references
while repairing a dangling reference and a markdown-vs-XML contradiction there.

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch; `session-state.md` (carry-forward) is the only prior artifact.

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Checked with | Result |
|---|---|---|
| #8290 open, bundle 4 of 5 | `gh issue view 8290 --json state` | OPEN — holds |
| #8292 must stay open | `gh issue view 8292 --json state` | OPEN (product-roadmap, unrelated scope) — the plan never names it in a closing keyword |
| PR #8405 / #8284 not collisions | parent-cleared; `gh pr view 8405 --json files` | #8405 merged 2026-09-20, landed the no-list at `knowledge-base/project/rejected/` (README + one entry) and `scripts/lint-rejected-register.sh`; #8284 open, docs only |
| "Rejected-request register from bundle 3" | `ls knowledge-base/project/rejected/` | **Renamed at ship.** It is the *rejected-concepts record* ("the no-list"); README says it is deliberately *not* called a register. The plan uses the shipped name |
| 16 candidate skills exist | `ls plugins/soleur/skills/<name>/SKILL.md` | **15 of 16.** `flag-bootstrap/` holds only `SETUP.md`, a runbook, not a skill. There is no frontmatter to flip. **Stale premise** |
| "B_ALWAYS delta" of the flip | `scripts/lint-agents-rule-budget.py:186` (`b_always = b_index + b_corpus`) | **Conflated budgets.** `B_ALWAYS` sums `AGENTS.md` + `AGENTS.rules.md` only. Skill descriptions are a *different* always-loaded budget, the harness skill listing, gated in-repo by `SKILL_DESCRIPTION_WORD_BUDGET` (`plugins/soleur/test/components.test.ts:21`). The flip's `B_ALWAYS` delta is **0 B by construction**. The plan records it as a measured 0, not an assumed one (AC-B1) |
| ADR-151 headroom "~1,453 B to warn" | `python3 scripts/lint-agents-rule-budget.py` → `[OK] B_ALWAYS=42920` | **Stale by +373 B.** Live: **1,080 B** to warn (44,000), **3,080 B** to reject (46,000). ADR-151:315 recorded 42,547 |
| `disable-model-invocation` works for plugin skills | Two open upstream bugs say otherwise: anthropics/claude-code#22345 (flag ignored for plugin skills) and #92769 (flagged plugin skills also hidden from the user) | **Refuted for the version in use, by probe** (see below). #22345 does not reproduce on 2.1.278. #92769's user-side failure does not reproduce on the headless `-p "/<plugin>:<skill>"` path. The interactive TUI `/` menu on Linux is **not** probed. It becomes work-phase gate W0 |
| `use-xml-tags.md` dangling | `ls` + `git grep -n use-xml-tags` | Holds. Missing. Cited at `workflows/create-domain-expertise-skill.md:3`, `workflows/create-new-skill.md:9`, `workflows/audit-skill.md:8`, `references/skill-structure.md:32` |
| core-principles vs skill-structure contradiction | read both | Holds. `core-principles.md:185-187` says markdown headings, no XML tags. `skill-structure.md:1-8` (`<critical_rule>`) and `:333-359` (pitfall) say remove ALL markdown headings and use pure XML. `audit-skill.md:63-66` audits against the XML side |
| "every shipped Soleur skill is markdown-headed" | awk over the body of each of the 102 `plugins/soleur/skills/*/SKILL.md` | Holds: **102/102** use `#` headings. 4 also carry top-level XML tags (`agent-native-architecture`, `compound-capture`, `dhh-rails-style`, `heal-skill`) |
| Zero hits for the six authoring terms | `grep -rE "leading word\|cognitive load\|context pointer\|premature\|co-location\|single source of truth" plugins/soleur/skills/skill-creator/references/` | Holds: 0 |
| 53/98 rules carry a prohibition, 10 lead with one | token count over `[id:` lines | 98 rules (holds). With a broader token set (`never\|do not\|don't\|must not\|no \|forbidden\|avoid`) the prohibition count is 56, so the issue's 53 depends on which tokens are counted. **10 lead with a negative imperative: holds**. The list is at §B5 |

**The upstream-bug probe (Phase 0.6 item 5: run it once before designing).** A throwaway plugin
`probe8290` (skills `flagged` with `disable-model-invocation: true` and `open` without it) was loaded
with `claude -p --plugin-dir` on Claude Code **2.1.278**, with transcripts in the session scratchpad:

| Probe | Result |
|---|---|
| `--setting-sources project` (probe plugin alone): model quotes both descriptions | `open` → quoted verbatim. `flagged` → **ABSENT**. The description is removed from the model's listing |
| `-p "/probe8290:flagged"` (headless user slash) | `SENTINEL-FLAGGED-RAN`. **User invocation works headless** |
| "Use the Skill tool to invoke probe8290:flagged" | `tool_use_error: Skill probe8290:flagged cannot be used with Skill tool due to disable-model-invocation. Ask the user to run /probe8290:flagged themselves`. **The model is refused and told to hand off** |
| Same for `probe8290:open` | `Launching skill` → `SENTINEL-OPEN-RAN` (control) |

**Side finding that changes the value case.** With the full user plugin set loaded (soleur + others,
129 skills), the model self-reports that on **haiku-4.5 (200k window) only 11 skills show a
description and 115 are name-only**. On **sonnet-5**, 128 show a description. That matches the
documented `skillListingBudgetFraction` (default 2% of the window): *"when the listing is over the cap,
Claude Code keeps every skill's name but drops the descriptions of the least-used skills"*
(code.claude.com/docs/en/settings-reference). The figures are the model's self-report, not a
harness counter. They are directional evidence, and the plan does not assert them as exact. The
repo's word cap is therefore a proxy for a real harness cap that is **already exceeded on 200k-window
models**. Each description removed from the listing lowers the competition among the model-invocable
skills that remain.

### Property List (Phase 0.6b)

- **P1.** A skill that only a human ever needs to fire costs the model's always-loaded skill listing nothing.
- **P2.** No surface the model executes directs it to invoke a skill it cannot invoke. That covers routing tables, orchestrator skills, agents, always-loaded rules and web Command Center dispatch.
- **P3.** The in-repo description budget counts what the model actually sees. The budget gate stays honest after P1.
- **P4.** The saving is measured, on the budget it lands in, and recorded against ADR-151's headroom. That record states that the `B_ALWAYS` delta is 0 and why.
- **P5.** Whether positive phrasing of an always-loaded rule steers better than a prohibition is **measured before** any rule body changes. The measurement is re-runnable and its verdict is recorded either way.
- **P6.** A future skill author meets four levers in the skill-creator references: leading words, the two loads, co-location, and criterion demand. The invocation choice sits under the two loads.
- **P7.** The skill-creator references give one answer to "markdown or XML", and no skill-creator pointer resolves to a missing file.
- **P8.** Every file taking peer prose carries the MIT attribution comment. `plugins/soleur/NOTICE` lists every file that does.

### Cut List (Phase 0.6b)

- **Flip `flag-bootstrap`** → P1 → cut. It is not a skill: there is no `SKILL.md` and no listing entry, so there is nothing to remove.
- **Flip `trigger-cron`** → P1 → cut, because it would break P2. The always-loaded rule `hr-no-dashboard-eyeball-pull-data-yourself` (`AGENTS.rules.md:56`) lists `soleur:trigger-cron` in the agent's own pull-it-yourself toolchain. `incident/SKILL.md:43` (Phase 0), `gdpr-gate/SKILL.md:270` (step 5) and `reproduce-bug/SKILL.md:68` do the same. This is a model-invoked skill by the peer's own test: *"could the model usefully reach for this autonomously?"* The repo-research pass classified it SAFE. The subject sweep (carry-forward error 1) reversed that.
- **Flip `invoice`** → P1 → cut, because it would break P2 on the web product. `invoice` is the founder's get-paid capability (ADR-107). The web Command Center reaches every skill **only** through the model: `apps/web-platform/server/prompt-injection-wrap.ts:25` ends each user turn with *"Invoke /soleur:go on the user's intent."* A user-invoked skill is therefore unreachable from the web product. The other 13 candidates operate Soleur's own infrastructure (Flagsmith, Doppler `soleur`, Cloudflare/Hetzner/GitHub provisioning, the admin allowlist, `users.role`). The two cron verbs (`cron-list`, `cron-delete`) stay reachable through `soleur:schedule`, which carries the identical list/delete steps (`schedule/SKILL.md:732,771`).
- **Flip `flag-list`** → P1 → cut at plan-review (R1). It is a read-only drift audit that the agent must be able to pull itself under `hr-no-dashboard-eyeball-pull-data-yourself`, and it is the blast-radius step `flag-delete` calls.
- **Rewrite each flipped description into a human-facing one-liner** (peer's SKILL-MECHANICS advice) → P1 → cut. P1 is fully bought by the flag, since the description leaves the listing whatever its wording. A rewrite is churn in 12 files for no measured property.
- **A repo-wide dangling-reference guard for all skills** → P7 → cut. A lexical sweep over all skills is dominated by cross-skill false positives (measured: 30+ hits, mostly `../other-skill/references/…`). P7 is scoped to skill-creator, and one work-time grep AC buys it.
- **Write `use-xml-tags.md`** → P7 → cut. The markdown decision (102/102 measured) makes the XML reference's subject the thing being retired. Delete the four pointers instead.
- ~~**A committed deterministic fixture test for the B5 eval** → P5 → cut.~~ **Reversed at plan-review (R10, deepen pattern-review 1).** The verdict decides whether a public record is written, so its precedence is pinned by the committed battery `test/rule-phrasing.test.sh`. That battery follows the house `test/*.test.sh` style, auto-registers via `test-all.sh:79` `plugins/soleur/skills/*/test/*.test.sh`, and carries the house floor shape so `guard-vacuity-floor` can construct its mutant (carry-forward error 8). The arm anti-confound check stays a recorded `diff` (AC-E2).
- **Register the B5 eval in `gated-skills.json`** → P5 → cut. There is no source block to gate: the rules live in `AGENTS.rules.md`, outside the registry's `plugins/soleur/` scan root. Adding `eval-gate:block` markers there would cost always-loaded bytes. The `tool-selection` measurement-only target (not in `gated-skills.json`) is the precedent.
- **Attribution comment inside `AGENTS.rules.md`** (only if B5 extends) → P8 → cut. The file would take a *technique*, not peer prose. A comment there costs `B_ALWAYS` bytes. NOTICE and the ADR carry the credit.

### Repo facts that constrain the plan (all measured)

- **Skill description budget:** `node` one-liner from
  `knowledge-base/project/learnings/2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`
  → `Total 2561 / 2561 headroom 0`. The budget is at zero headroom now.
- **The 15 existing candidates** total 372 words: admin-ip-refresh 24, cf-token-scope 34, cron-delete 29,
  cron-list 27, flag-create 18, flag-delete 37, flag-list 33, flag-set-role 20, invoice 39,
  provision-{cloudflare,doppler,github,hetzner} 14 each, trigger-cron 34, user-set-role 21.
  The first flip set of 13 (minus invoice and trigger-cron) totalled 299 words / 1,959 B. **The final flip set of 12** also keeps
  `flag-list` (plan-review R1) and totals **266 words / 1,733 bytes** of description.
- **Budget test counts every skill:** `components.test.ts:150-170` sums `frontmatter.description` over
  `discoverSkills()` with no invocation filter. Flipping without editing the test buys **no in-repo headroom**.
- **The repo already knows the axis:** `components.test.ts:1329-1346` pins `skills/{go,help,sync}` as
  model-invocable with `user-invocable: false`, and explains `disable-model-invocation: true` as "the
  dispatch regression". No skill uses the key today.
- **Harness mirrors:** only `go`, `help`, `sync` are mirrored under `plugins/soleur/{devin,codex}/skills/`,
  so no flipped skill has a mirror. No Soleur skill carries an `agents/openai.yaml` (Codex's
  `policy.allow_implicit_invocation`). On Codex, Devin and Grok the key is **expected inert**:
  descriptions still load and nothing regresses. That is unverified; work gate W0 probes Devin and
  Codex.
- **Cloud-mode marker population** (`plugins/soleur/test/devin-cloud-mode.test.ts:460-466`, `:892-906`)
  lists 10 of the 12 flipped skills (all but the two cron verbs). The marker lives in the body, so frontmatter edits do not touch it.
- **ADR-226 (canonical references):** agent-read prose names a skill `soleur:<name>`, and the slash
  form is non-canonical and RED under `harness-parity-tree.test.ts`. So an operator-facing reference
  to a user-invoked skill **cannot** be told apart lexically by a `/` sigil. Guard 1 uses an ack
  table instead of a lexical rule.
- **B5 rule-body gate:** `scripts/lint-rule-bodies.py:104` `GATED_PREFIX_RE = ^(hr|wg)-`. Any body
  change to an `hr-`/`wg-` rule requires a `.claude/rule-weakening-acks.txt` ack. Rule ids are
  immutable (`cq-rule-ids-are-immutable`, `scripts/lint-rule-ids.py`). The per-rule cap is 600 B.
- **eval-harness shape:** closed-enum classification, `measure-classification.cjs` +
  `gate-classification.cjs` asserts, `providers: file://models.generated.json` (opus-5, sonnet-5,
  haiku-4.5), opt-in and manual (not CI-wired), measurement-only precedent
  `promptfooconfig-tool-selection.yaml`. `test/registry-completeness.test.sh` scans
  `eval-gate:block:<id>:start` under `plugins/soleur/` (excluding eval-harness/), so **no new file
  may contain that literal**.
- **Next ADR ordinal:** `origin/main` tops out at ADR-234, and **two open PRs already claim ADR-235**
  (#8384, #8329). This plan takes **ADR-236, provisionally**, and re-derives it before merge (Phase 6).
- **Peer sources, pinned SHA `c55ee46073ed923f86ce59a5eb3b6d895095d1b7`** (fetched read-only with
  `gh api repos/mattpocock/skills/contents/<path>?ref=<sha>`):
  `skills/productivity/writing-for-agents/SKILL.md` (81 lines: context pointers, the two loads,
  co-location, completion criteria (clarity/demand), leading words, negation, pruning),
  `skills/productivity/writing-for-agents/SKILL-MECHANICS.md` (22 lines: invocation, splitting by
  invocation, router skills), `.agents/invocation.md` (user- vs model-invoked; *"no other skill can"*
  reach a user-invoked skill).
- **No open code-review overlap** (see §Open Code-Review Overlap). **No open PR** touches skill-creator,
  the candidate skills, or eval-harness. `#7390` (stale WIP) touches `AGENTS.rules.md`, which matters
  only if B5 extends.

### Institutional learnings that bind this plan

- **Carry-forward errors 1-8** (`knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/session-state.md`).
  How each applies:
  1. *Sweep on the subject.* The invoker sweep ran on the bare skill name (`git grep -w <name>`), not
     on `soleur:<name>`, and it overturned the SAFE verdict on `trigger-cron`. Guard 1 scans **both** forms.
  2. *Parse YAML for job-graph claims.* The plan makes no CI job-graph claim. If ship-time CI
     triage needs one, answer it with `python3 -c 'import yaml…'`, never awk.
  3. *Normalise timezones.* Eval timing and any merge-rate reasoning use `%cI` / `TZ=UTC`.
  4. *Repo-global ratchets.* Phase 5 runs them by their own invocations before the first push.
  5. *CI-skip token in squash prose.* The plan, PR body and commit messages discuss no CI directive.
     `bash scripts/lint-squash-ci-directives.sh` runs over the PR body before merge.
  6. *Reverted file still cited in the PR body.* A revert re-scans the body with the gate's own extractor.
  7. *Notes off `/tmp`.* Eval outputs and probe transcripts that must survive go under
     `knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/`, never `/tmp`.
  8. *Stage-then-run.* Every new test file is `git add`-ed before its ratchet runs, and any new floor
     copies the house sentinel `FATAL: anti-vacuity: only N assertion(s) executed, floor is M.` verbatim.
- `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`: read the cap from the
  test, never from memory. The learning's own 1800 figure is stale; the live figure is 2561.
- `2026-06-30-eval-fixture-bug-inverts-gate-verdict-and-web-vs-cli-skill-shape.md`: disaggregate
  eval deltas **by model**. A pooled win can hide one model's regression. This is written into the
  B5 decision rule.
- `2026-07-27-my-ab-could-not-resolve-the-effect-i-concluded-from-it.md`: an A/B is noise-floor
  limited. The B5 threshold is stated as a multiple of the run's own standard error, not as a raw ε.
- `2026-06-29-eval-gate-target-validity-and-three-map-drift.md`: a surface is a valid eval target
  only if its prose **is** the LLM-applied decision rule. Always-loaded rule bodies are such prose.
  The four chosen rules are ones a model applies by reading (the hooks that also back two of them do
  not run inside promptfoo).
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` and
  `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md`: Guard 1
  needs harness rows and a row validated against the **post-flip** tree.
- `2026-04-23-agents-md-governance-measure-before-asserting.md`: re-measure `B_ALWAYS` at work time
  and again pre-push, and quote the command output.
- `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md`: every rule id
  this plan cites was grepped from `AGENTS.rules.md` on this branch (AC-X4 re-checks them).
- Bundle-3 learnings (cited in that plan's §Institutional learnings): design pass before panel;
  never classify a multi-file failure from its first failure; the generated-artifact-conflict
  learning (ADR-229) for `knowledge-base/INDEX.md` if touched.

### Peer overlap (Phase 1.5b)

functional-discovery searched 3 registries and found **no overlap that replaces this work**. The
nearest hits were Anthropic `skill-creator` (authoring guidance with no invocation-axis or
leading-word coverage) and promptfoo skills. Soleur's `eval-harness` already covers promptfoo.
Nothing was installed. Community-stack check: no uncovered stack, so it was skipped.

### External research decision (Phase 1.6)

Skipped beyond the one authoritative lookup. The only external question was Claude Code's semantics
for `disable-model-invocation`, which has two conflicting open upstream bugs. It was answered by a
**probe on the installed version**, which is stronger evidence than any doc for this repo's runtime.

## Research Reconciliation — Issue Body vs. Codebase

| Issue claim | Reality (measured) | Plan response |
|---|---|---|
| 16 human-only candidates, all flippable | 15 exist. `flag-bootstrap` is a runbook dir. `trigger-cron` is named as the **agent's own** pull-it-yourself tool in an always-loaded `hr-` rule and three skills. `invoice` is a founder-facing capability the web Command Center reaches only through the model | Flip **12**. Keep `trigger-cron`, `invoice` and (after plan-review R1) the read-only `flag-list` model-invocable, pinned by test with the reason (Guard 1c). Drop `flag-bootstrap` |
| The invocation axis is "a second lever" on ADR-151's headroom | `B_ALWAYS` = `AGENTS.md` + `AGENTS.rules.md` bytes only (`lint-agents-rule-budget.py:186`). Descriptions live in the harness skill listing | Record `B_ALWAYS` Δ = **0 B** (measured before and after). Record the real saving on the budget it lands in: **−266 words / −1,733 B** of listing text. Add an ADR-151 addendum so the conflation is not re-made |
| ADR-151 records "~1,453 bytes of headroom" | Live 42,920 B → **1,080 B** to warn | The addendum restates the live figure with its command. Every number carries the command that produced it |
| Flipping removes the description "entirely" | True on Claude Code 2.1.278 (probed). Inert on harnesses that ignore the key. Upstream #92769 reports hidden-from-user on Windows | Work gate W0 re-probes on the real plugin. Devin/Codex outcomes are recorded as measured or as UNVERIFIED, never assumed |
| "53 of 98 rules carry a prohibition" | 98 holds. The prohibition count is token-set dependent (56 with a broader set). 10 leading-negative holds | The plan cites 10/98 (the only number its design uses) and names the token set wherever it quotes a count |
| "the rejected-request register from bundle 3" | Shipped as the rejected-concepts record ("the no-list"). Its README scopes it to refused **concepts**; refused **mechanisms** belong in ADR alternatives tables | If B5 is rejected, write the no-list entry the operator directed, keyed on the *capability a founder would ask for*. Also record the mechanism in ADR-236's alternatives table, and surface the README tension as a Decision Challenge (D6) |
| `use-xml-tags.md`: "delete or write" | 102/102 shipped skills are markdown-headed | **Markdown.** Delete the four pointers and write no XML reference |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --limit 200` (69 open) and matched each planned
path and skill name with a standalone `jq --arg ... contains($path)`: `skill-creator`,
`components.test.ts`, `AGENTS.rules.md`, `eval-harness`, every flipped skill name, `invoice/SKILL`,
`trigger-cron`, `NOTICE`, `go-routes`, `skills.js`.

None. No open scope-out names a file this plan touches.

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) an operator types `/soleur:flag-list` (or any of
  the 12) and the harness does not find it, or fuzzy-matches another skill (the upstream #92769
  shape), so a routine flag/cron/provisioning task stalls; or (b) a model-invocable workflow tells
  the agent to run a now user-invoked skill. The agent then gets a Skill-tool refusal mid-pipeline
  and a headless run stops on a hand-off nobody is present to take; or (c) if B5 extends, a
  rephrased always-loaded rule steers every session slightly worse on the behaviour it governs,
  with no error anywhere.
- **If this leaks, the user's workflow is exposed via:** nothing new. No data surface, credential,
  or network path is added or changed. The B5 eval sends synthetic scenario text plus the **full**
  public `AGENTS.md` + `AGENTS.rules.md` corpus (~43 KB; its only email is `noreply@anthropic.com`, and
  it holds no secrets) to the Anthropic API under the operator's own key. That is the harness's
  documented, opt-in use.
- **Brand-survival threshold:** `aggregate pattern`. Failure (c) is by nature a diffuse, many-session
  degradation, and (a) and (b) hit operator tooling, not a tenant's data. No single-user incident is
  reachable.

*Scope-out note:* the diff touches no path matched by preflight's `SENSITIVE_PATH_RE`.

## Architecture Decision (ADR/C4)

Detection fires: the plan creates a **new cross-cutting invariant** (which skills may be user-invoked,
and what the description-budget gate counts) and **extends ADR-151's record** (the headroom figure
and the list of shrink levers).

### ADR

- **Create ADR-236 (provisional ordinal)**, *Human-only skills are user-invoked; the description
  budget counts what the model sees.* Decision:
  1. A skill takes `disable-model-invocation: true` **only if** (necessary, not sufficient; membership is D1's list, fixed by the pin) (K1) no model-read surface directs the agent
     to invoke it; (K2) it is not a founder-facing capability that the web Command Center (which
     reaches skills only through `/soleur:go`, `prompt-injection-wrap.ts:25`) must reach; and (K3)
     its capability is not otherwise stranded.
  2. `SKILL_DESCRIPTION_WORD_BUDGET` counts only model-invocable skills, and the freed words are
     banked by ratcheting the cap down.
  3. Guard 1 is the enforcement.

  Alternatives table: flip all 16 (rejected: breaks `hr-no-dashboard-eyeball-pull-data-yourself`
  and the web invoice path); `user-invocable: false` (inverse axis, rejected); rewrite descriptions
  to one-liners (cut: no property); a router skill (the peer's cure for cognitive load. Not needed:
  `soleur:help` already renders the full list); **positive-phrasing rewrite of the rule corpus**
  (row filled with the B5 verdict and the eval command either way).
  Measured table: 12 skills, 266 words, 1,733 B, `B_ALWAYS` Δ 0 B, probe results with version, and
  per-harness status (Claude Code measured; Devin/Codex measured-or-UNVERIFIED; Grok inert by
  construction: its adapter Reads `SKILL.md` directly).
- **Amend ADR-151**: append `## Addendum — 2026-09-21 (#8290): the invocation axis is not a B_ALWAYS lever`
  (≤ 15 lines): live `B_ALWAYS` 42,920 B (the command), live headroom 1,080 / 3,080 B, and the flip's
  measured 0 B Δ with the reason. The shrink levers for `B_ALWAYS` remain trim-prose and migrate-a-rule.
  The invocation axis relieves a *different* always-loaded budget (ADR-236). If B5 extends, the
  addendum also records the rewritten rules' measured `B_ALWAYS` Δ.

### C4 views

**No C4 impact.** Checked against all three files, not by keyword grep. `model.c4` (820 lines),
`views.c4` (104), `spec.c4` (54):

- *External human actors:* founder, operator. No actor is added. The founder→Codex/Devin/Claude
  "invokes Soleur skills" edges stay true, since user invocation is kept.
- *External systems/vendors:* none added. The B5 eval uses the Anthropic API through the existing
  eval-harness, and no C4 element models the eval-harness's provider calls today (`evalharness`
  component: "Validation-gates classifier-skill block edits"). That description stays true, because
  a measurement-only target changes no gate.
- *Containers/data stores:* `skills` ("Markdown SKILL.md") and `skillloader` ("Discovers and loads
  skills, agents, commands") keep their membership and behaviour. The invocation axis is a
  frontmatter property *within* the Skills container.
- *Access relationships:* no actor↔surface relationship changes owner or cardinality.
- *Derived cardinalities:* no skill, agent, command, monitor or workflow is added or removed.
  Backed by a green `bash plugins/soleur/test/c4-count-parity.test.sh` run in Phase 5 (AC-X6).

### Sequencing

Both ADR edits land in this PR (Phase 4). ADR-236's alternatives row for positive phrasing is
written **after** the B5 verdict (Phase 3) so it records a measured outcome.

## Observability

The surface this change creates has no runtime process. It consists of shipped skill frontmatter, a
bun test guard, and an opt-in eval. So the "liveness" of the change is the CI gate that fails when it
is broken, and the declared probe reads the shipped artifact itself. (deepen-plan Phase 4.7 fired: the
Files-to-Edit include `.ts`/`.cjs` code, so the earlier prose-only "not triggered" note was
non-compliant.)

```yaml
liveness_signal:
  what: "bun test plugins/soleur/test/invocation-axis.test.ts (Guard 1) and the components.test.ts budget test, run by the ci.yml test matrix (scripts/test-all.sh shards) and by the lefthook plugin-component-test hook"
  cadence: "every PR and every push to main (CI), every commit touching plugins/soleur (lefthook)"
  alert_target: "the PR's required CI check turns red; on main, the existing post-merge CI failure notification"
  configured_in: ".github/workflows/ci.yml test matrix (lines ~881-912, scripts/test-all.sh per shard) and lefthook.yml:357 plugin-component-test"
error_reporting:
  destination: "CI job log + the Guard 1 failure message (file:line, skill, form, allowed reasons, two exits, ADR-236 pointer)"
  fail_loud: "yes: an unacked referrer, a stale ack, a dead glob (per-glob floor), scanned-count != ls-files count, or a pinned skill gaining the key each exit non-zero"
failure_modes:
  - mode: "a model-read surface starts directing the agent to invoke a user-invoked skill"
    detection: "Guard 1 unacked-referrer test (G1-G4 :(glob) pathspecs)"
    alert_route: "red required CI check on the PR that introduces it"
  - mode: "a skill that must stay model-invocable (trigger-cron, invoice, flag-list, go/help/sync) gains disable-model-invocation"
    detection: "Guard 1(c) keep-pins in components.test.ts"
    alert_route: "red required CI check"
  - mode: "Claude Code upgrade changes flag semantics (e.g. upstream #92769 shape: flagged skill hidden from the user)"
    detection: "soleur:model-launch-review per-release checklist re-runs the W0 probe recorded in ADR-236; soleur:postmerge repeats the tmux TUI capture after this release"
    alert_route: "action-required issue filed by those skills; ADR-236 rollback trigger (revert the 12 keys)"
  - mode: "an unattended run hits a Skill-tool refusal for a user-invoked skill"
    detection: "the harness tool_use_error text 'cannot be used with Skill tool due to disable-model-invocation' in the run transcript"
    alert_route: "the run's own action-required issue per the ADR-236 headless-refusal policy"
  - mode: "the B5 eval run is truncated, errors, or exceeds the spend cap"
    detection: "rule-phrasing-verdict.cjs precedence step 1 returns ABORTED"
    alert_route: "b5-eval-results.md records ABORTED; one rerun, else B5 split to its own issue"
logs:
  where: "CI job logs (GitHub Actions retention); W0 transcripts and eval results committed under knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/"
  retention: "CI per the repo's Actions retention setting; committed artifacts permanently in git"
discoverability_test:
  command: "grep -c '^disable-model-invocation: true' plugins/soleur/skills/flag-create/SKILL.md"
  expected_output: "1"
```

Under W0-STOP the flip does not land, and `discoverability_test` then prints `0`. In that profile the
probe is replaced by `grep -c 'status: proposed' knowledge-base/engineering/architecture/decisions/ADR-236-human-only-skills-are-user-invoked.md`,
with expected output `1`.

## Encryption Posture / Infrastructure (IaC) / GDPR

- **Encryption posture:** not triggered. No persistent store and no new cross-component connection.
- **IaC:** not triggered. No server, secret, vendor account, DNS or cron is introduced. The flipped
  skills keep their existing, already-provisioned behaviour.
- **GDPR gate:** not triggered on the canonical regex. Triggers (a)-(d) checked: (a) the B5 eval
  sends synthetic scenarios and public rule text, not operator-session-derived data; (b) threshold
  is `aggregate pattern`; (c) no cron reads learnings/specs; (d) no *new* distribution surface (the
  existing plugin release carries the change).

## Guard Contract

There are two guards. Their matrices were written from the design before any guard code existed. They
were revised twice after review. The first pass was the domain-leader and advisor trims. The second
was the 9-seat panel, whose simplification and correctness seats both fired on Guard 1. Where both
fired on the same scope, the delete won: the bare-name durable scan, the `headless-slash` and
`script-path` reasons, and the redundant rows are cut. Where only the correctness side fired, the
assembly grew instead: shipped plugin hooks, harness lib and Inngest prompts.

### Guard 1 — invocation axis (new `plugins/soleur/test/invocation-axis.test.ts`; the budget filter itself stays in `components.test.ts:150-170`)

**Property.** Every skill whose frontmatter sets `disable-model-invocation: true` satisfies three
conditions:

- **(a)** it is excluded from the description-budget count;
- **(b)** a model-read instruction or dispatch surface names it only at a (file, skill) pair listed in
  a reviewed ack table, with an ack reason that is a non-model mode (`doc-mention` or
  `operator-handoff`);
- **(c)** it is not one of the pinned must-stay-invocable skills (`go`, `help`, `sync`, `trigger-cron`,
  `invoice`, `flag-list`).

**Assembly.**

*Members are derived, never listed.* `USER_INVOKED = discoverSkills()`, filtered on
`parseComponent(p).frontmatter["disable-model-invocation"] === true`. The budget test uses the same
parse, so "is this skill user-invoked" has one chokepoint. An exact-set pin
(`expect([...USER_INVOKED].sort()).toEqual([12 names])`) makes any 13th flip a reviewed edit. That
edit must also move ADR-236's list and lower the cap, and the failure message says so (spec-flow P2).

*Referrer population.* Every entry is a **`:(glob)` pathspec**. Plain git pathspecs do not recurse
`**`, and measured: `git ls-files 'knowledge-base/engineering/operations/runbooks/**/*.md'` → 0, while the
`:(glob)` form → 79. Git has no `{a,b}` brace expansion, so each alternative is its own pathspec
(Kieran P1-6). The floors are **named constants**, never derived from the population they guard.
The precedent is `workflow-file-size.test.ts:44` `LIVE_MIN_FILES`, one per glob, for example
`MIN_RUNBOOK_FILES`. A count-equality test (precedent: `harness-parity-tree.test.ts:89-106`) compares the
scanner's examined-file count against `git ls-files` run on a **separate literal pathspec list**, not the
scanner's own glob constant. If both sides shared one constant, narrowing a glob would move both and
stay green (deepen pattern-review 3). Files are enumerated with
`execFileSync("git",["ls-files","--full-name","--",spec])` (tree `:34-38`). The globs:

- **G1 (always loaded):** `AGENTS.md`, `AGENTS.rules.md`.
- **G2 (what the plugin ships and the model reads):** separate pathspecs for
  `plugins/soleur/skills/**/*.md`, `plugins/soleur/agents/**/*.md`, `plugins/soleur/commands/*.md`,
  `plugins/soleur/devin/**/*.md`, `plugins/soleur/codex/**/*.md` and `plugins/soleur/hooks/**` (the shipped SessionStart
  injectors, such as `codex-session-start.sh` and `devin-session-start.sh`), and
  `plugins/soleur/lib/**/*.ts` (the harness routing text).
- **G3 (model-dispatch prompts):** `apps/web-platform/server/inngest/**/*.ts` (the cron prompts),
  `.github/workflows/*.yml`, and `.claude/hooks/**`.
- **G4 (agent-read runbooks):** `knowledge-base/engineering/operations/runbooks/**/*.md`.

*Hit forms.* A hit is canonical `soleur:<name>`, or the path form `skills/<name>/`. The bare-subject
form stays in the **one-time** sweeps: Phase 0 step 3, and the Phase 1 read of the exempt group. It is
not a durable scan, because its hits in prose are doc-mentions that only grow the table (CTO devex,
simplicity).

*Exempt by construction.*

- A hit inside `plugins/soleur/skills/<name>/` itself.
- A hit inside **another flipped skill's** directory. A user-invoked skill runs only after a human
  typed it, and it cannot Skill-invoke a flipped sibling. Phase 1 step 3 reads this exempt group
  **once** and rewrites any operative sibling call (spec-flow P1).

*Deliberately outside the assembly, with the reason stated in the test.*

- ADRs, because they record decisions rather than instruct.
- `apps/web-platform/**` outside `server/inngest/`. Web user turns reach skills only through the
  `POSTAMBLE` constant in `server/prompt-injection-wrap.ts`.
- `apps/web-platform/supabase/migrations/**`. Migration 054's error text names `soleur:user-set-role`
  for a human. Applied migrations are immutable, and a model that follows the text gets the harness's
  graceful hand-off.
- `scripts/**` and `plugins/soleur/scripts/**`: human-facing output.
- `plugins/soleur/docs/**`, `README.md` and `commands/help.md`: human-read listings (ADR-226 §4).

*The failure message (CTO devex).* On RED the message prints file:line, the skill, and the matched
form. It lists the two allowed reasons, names the two exits ("rewrite the referrer as a hand-off, or
keep the skill model-invocable"), and points to ADR-236. The ack table is one labelled constant at the
top of the `describe` block.

**Mutation matrix.** Each row names the test that must fail (test-design finding 3).

| # | Edit (to the system under test) | Must drive RED — which test |
|---|---|---|
| M1 | append `Then run soleur:flag-create.` to `plugins/soleur/skills/ship/SKILL.md` | `no unacked referrer` (G2) |
| M2 | add an unacked `soleur:user-set-role` referrer, the last member in sort order, to a runbook, leaving the pin intact | `no unacked referrer` (G4). This is the second-member row: the check must not stop at the first member |
| M5 | add `disable-model-invocation: true` to `trigger-cron` | `must-stay-invocable pins` (c) |
| M6 | add an ack row for a (file, skill) pair that has no hit | `no stale ack` (set identity) |
| M7 | point each group's first glob at a nonexistent path, one group per run (dispatch) | `files examined >= 1` for that glob |
| M8 | reorder: apply the invocation filter to the reporting list **after** summing the total | `cumulative description word count under budget`: the total stays unfiltered against the ratcheted cap. This is the ORDER row for (a) |
| M9 | add `run soleur:cron-list` inside a string literal in an `apps/web-platform/server/inngest/functions/cron-*.ts` prompt | `no unacked referrer` (G3) |

**Harness rows.**

| # | Edit (to the suite, not the guard) | Expected |
|---|---|---|
| H2 | delete every ack row | RED with the full unacked list, which proves the table is consulted |
| H3 | stub the scanner so it returns zero files (and, separately, narrow one scanner glob while the literal list is unchanged) | RED from the scanned-count = `ls-files`-count assertion, not from the hit list |
| H4 | must-PASS, non-canonical: runbook line `The operator types /soleur:provision-hetzner <slug>` with an `operator-handoff` row | GREEN |
| H5 | must-PASS: `plugins/soleur/skills/flag-create/SKILL.md` naming `soleur:flag-set-role` | GREEN (intra-flipped-family exemption) |

**The precondition-holds-property-fails row (stated blind spot).** The guard sees sites, not
semantics. A `doc-mention` ack on a line that is in fact an operative model instruction satisfies it,
and so does a future operative call between two flipped skills. The mitigation is one-time and
procedural. Phase 1 step 3 reads every current hit, and the exempt group, and records the result. The
`schedule` and `trigger-cron` cron-verb lines and the `tenant-provisioning.md` lines are reworded. And
`operator-handoff` rows must read as a hand-off to a human in the prose itself, which a reviewer
checks against the diff.

**Validated against the post-remediation tree.** The remediation writes text into G2 and G4. That
covers `authoring-levers.md`, `skill-structure.md`, `official-spec.md`, `audit-skill.md`, the reworded
`schedule`/`trigger-cron` lines, the `help.md` and `go.md` notes, and `tenant-provisioning.md`. New
prose names no flipped skill and uses the synthetic `my-deploy-skill` instead. Two sites must name
one: the `go.md` hand-off note and the runbook lines. Each gets an `operator-handoff` row. AC-A3
asserts that the ack-row count equals the count the guard prints on the finished tree, and that each
mutation row turns RED in the named test.

**Anchor.** The ack table, the exact-set pin and the ratcheted cap all live in the same commit as the
change. The guard therefore proves consistency, not integrity. For a weakening to pass, ADR-236's
measured table must also move, and a 13th flip must edit the pin, the ack table, ADR-236's list and
the cap. Four reviewed sites is the stated anchor. No WORM registry is invented.

### Guard 2 — the B5 measurement gate (pre-registered; `plugins/soleur/skills/eval-harness/scripts/rule-phrasing-verdict.cjs`)

**Property.** An always-loaded rule body is proposed for a positive-led rewrite **only** when all of
the following hold:

- a pre-registered A/B, run in the real always-loaded context on a generation surface, shows a
  task-clustered improvement of at least the minimum worthwhile effect (MWE);
- the interval excludes zero;
- no model regresses;
- the sign is consistent on at least 3 of 4 rules.

A null result is never recorded as more certain than the run's power allows. An aborted or invalid run
never produces a verdict.

**Assembly.** The pieces, with scoring in `scripts/measure-rule-compliance.cjs` (keyed on
`vars.rule`) and a battery `test/rule-phrasing.test.sh`. The battery follows the house `test/*.test.sh`
style (Kieran P1-5) and runs the observable sample table (H-E2) plus the E0-E9 fixtures. Its fixtures
live in `test/fixtures/rule-phrasing/`. It carries an anti-vacuity floor using the house sentinel
**verbatim**, `FATAL: anti-vacuity: only N assertion(s) executed, floor is M.`, and it is `git add`-ed
before its first run, because `guard-vacuity-floor.test.sh` walks `git ls-files` (carry-forward error 8).
The three panel positions were weighed: correctness and test-design argued for committed fixtures,
simplicity against. The correctness side won, because the verdict decides whether a public record is
written:

- **Fixture.** `prompts/rule-phrasing-bodies.json` maps each id to its `prohibition` body (pinned),
  its `prohibition_sha256`, and its `positive` body.
- **Arm generator.** `prompts/rule-phrasing.cjs` builds the three arms from the live `AGENTS.md` and
  `AGENTS.rules.md`. It **throws** if a live target body's sha256 differs from the fixture, so a rerun
  cannot silently compare stale text (CTO devex 5, spec-flow 8).
- **Tasks.** `tasks/rule-phrasing.jsonl` holds 24 generation tasks.
- **Scoring.** `scripts/measure-rule-compliance.cjs` follows the shape of `measure-classification.cjs:17-29`:
  `pass: true` plus `score` and `reason`, with no `metric` field (there is none in the house shape). It
  scores only the task's own rule observable. The reason prefix is `rule-compliant` or
  `rule-noncompliant`, so it parses the way `eval-gate.cjs:137` parses `classification-(in)?correct`.
- **Verdict CLI shape** (precedent `verdict.cjs:132` + `eval-gate.cjs:45-70,312`):
  - a pure exported `verdict(json)`;
  - a `require.main` guard;
  - one-line JSON output on stdout;
  - exit 1 fail-closed via `die()`, and exit 2 on bad arguments.
- **Battery floor shape** (precedent `plugins/soleur/test/lint-rejected-register.test.sh:1110-1126`):
  - a call-site case counter incremented in the `X=$((X + 1))` shape;
  - `MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}` as ONE simple assignment directly above the floor `if`;
  - the floor enforced by `printf '\nFATAL: anti-vacuity: only %s assertion(s) executed, floor is %s. The battery ran but did not assert.\n' ... >&2; exit 1`, and never through `fail()` (ADR-193);
  - a `passes + fails == cases` accounting check.

  With that shape, `guard-vacuity-floor.test.sh:531` can slice a mutant, so the floor scores FIRES,
  not CONSTRUCTION.
- **JS chat prompts are a first use.** Every existing config uses `file://prompts/*.txt`, so no
  `.cjs` chat-array prompt exists in eval-harness yet. The README row names it as a first use. Its
  gates are `promptfoo validate` plus a `node -e` render.
- **Verdict.** The committed module `scripts/rule-phrasing-verdict.cjs` exports `verdict(json)` and a
  CLI. It replaces the pasted one-liner (test-design finding 1). It applies checks in a fixed
  **precedence** (test-design finding 2):
  1. `ABORTED` if H-E1 fails: counts, results per cell ≠ the declared repeat, or any error row.
  2. V1 per rule. A rule failing V1 is excluded. If no rule passes, the verdict is `INVALID`.
  3. `REJECT-CEILING`.
  4. `EXTEND`.
  5. `REJECT`.
  6. `INCONCLUSIVE`.

  The verdict set is `{EXTEND, REJECT, REJECT-CEILING, INCONCLUSIVE, INVALID, ABORTED}` (spec-flow P0-2).
- **Synthetic checks.** The synthetic JSONs for the rows below are the committed battery fixtures,
  with no API calls.

**Mutation matrix.**

| # | Synthetic input | Must yield |
|---|---|---|
| E0 | a clear ≥ 15-pt, tight-interval win on all 4 rules in all 3 models | `EXTEND` (the positive control; a verdict that always says INCONCLUSIVE fails here) |
| E1 | the positive arm identical to the prohibition arm | not `EXTEND` (Δ≈0) |
| E2 | the `none` arm scores the same as prohibition on every rule | `INVALID` |
| E3 | E0 with the arm identities swapped | not `EXTEND`; the sign flips |
| E4 | E0 with one model regressing by more than ε | not `EXTEND` |
| E5 | the pooled win carried by 1 of 4 rules | not `EXTEND` |
| E6 | prohibition ≥ 0.95 on every V1 rule, and an interval upper bound below the MWE | `REJECT-CEILING` (ORDER: ceiling precedes REJECT) |
| E7 | an interval straddling both 0 and the MWE | `INCONCLUSIVE` |
| E8 | an interval with upper bound < MWE and prohibition < 0.95 | `REJECT` (the negative control) |
| E9 | one cell with 2 results where repeat = 3, or an error row | `ABORTED` |

**Harness rows.** H-E1 is the precedence step 1 check, so a truncated or errored run cannot yield a
verdict. H-E2 (must-PASS) covers a compliant generation that names the banned command inside a refusal
sentence: it must score compliant. The regexes target the command context, and the known false
negative is recorded. That false negative is a violation written in prose with inline backticks.
Before the run, the regexes are checked against a hand-written sample table.

**Anchor.** The fixture JSON (both body texts and the hash), the MWE, the observables and the
precedence are committed **before** the run. ADR-236 records the verdict module's sha256 next to the
raw rates. Moving a threshold after the numbers are known is a diff to committed files.

## Design Decisions

### D1 — Flip 12, keep 3, drop 1, each by a stated criterion

| Skill | Verdict | Criterion and evidence |
|---|---|---|
| flag-create, flag-delete, flag-set-role | flip | K1: referenced only by family siblings, naming-evidence prose and `flag-bootstrap/SETUP.md` (a human runbook). They operate Soleur's own Flagsmith and Doppler and are never a tenant capability |
| cron-list, cron-delete | flip | K3: the capability stays model-reachable through `soleur:schedule`, whose list and delete steps these verbs duplicate (`schedule/SKILL.md:732,771`) |
| provision-cloudflare, provision-doppler, provision-github, provision-hetzner | flip | K1: prose and script-path referrers only. `tenant-provisioning.md` names them in `**Skill:**` lines that are reworded to an explicit operator hand-off (COO) |
| admin-ip-refresh | flip | K1: human-facing text only (`README.md`, `server.tf` comments, `admin-ip-drift.md` in the typed `/soleur:` form). It mutates Doppler behind an explicit ack, so a human is in the loop regardless |
| user-set-role | flip | K1: sibling prose. The migration-054 error message names it for a human |
| cf-token-scope | flip | K1: `agent-browser/SKILL.md:495` lists it among Playwright consumers (prose) |
| **trigger-cron** | **keep** | fails K1: `AGENTS.rules.md:56`, `incident/SKILL.md:43`, `gdpr-gate/SKILL.md:270` and `reproduce-bug/SKILL.md:68` direct the **agent** to use it |
| **flag-list** | **keep** | fails the peer's own test, *"could the model usefully reach for this on its own?"*. It is a **read-only** drift audit, and `hr-no-dashboard-eyeball-pull-data-yourself` tells the agent to pull state itself. Hiding it would leave the agent unaware the audit exists, and a `list.sh` script-path escape reaches only where a document names the path (agent-native P1). It is also the blast-radius step `flag-delete:20` calls, which now keeps working unchanged |
| **invoice** | **keep** | fails K2: it is founder-facing (ADR-107), and the web Command Center reaches skills only through the model |
| flag-bootstrap | n/a | not a skill (it has no `SKILL.md`) |

**Operative references that change with the flip:**

- `flag-delete/SKILL.md:20` is **unchanged**. `flag-list` stays model-invocable, so the call works from
  inside the user-invoked flag-delete. No `script-path` escape exists anywhere. A script-path route to a
  *mutating* script would bypass the typed-yes gates: `flag-delete/scripts/delete.sh:146` is a plain
  `read -r -p` with no `[[ -t 0 ]]` check (agent-native P1). That pre-existing TTY gap is filed as a
  follow-up issue at work time, not fixed here.
- **The intra-flipped-family group is read once** (spec-flow P1). `flag-create:41,72` →
  `soleur:flag-set-role` and `cron-delete:37` → `cron-list`. Each line is classified, and any line
  telling the model to run a sibling becomes an explicit operator hand-off.
- `schedule/SKILL.md:732,771` and `trigger-cron/SKILL.md:26-27` describe the cron verbs as "first-class
  verbs". They are reworded so the verbs read as **human-typed** shortcuts, and the model runs the
  steps in place. Without this, a model reading "exposed as `soleur:cron-list`" could reach for the
  Skill tool and be refused (CTO finding 4).
- `knowledge-base/engineering/operations/runbooks/tenant-provisioning.md:59,98,135,169,319`: each
  `> **Skill:** soleur:provision-<x> …` line becomes "The operator types `/soleur:provision-<x> …`"
  (COO finding). Runbooks are outside ADR-226's plugin-doc population, so the typed slash form is
  correct there.
- `plugins/soleur/skills/schedule/SKILL.md` **description** already reads "creating, listing, or deleting
  scheduled agent tasks". So the K3 route for cron-list and cron-delete is discoverable from the listing
  itself, and no description edit is needed (agent-native P2, verified).
- `plugins/soleur/commands/help.md`: the SKILLS block marks each skill whose frontmatter sets
  `disable-model-invocation: true` as `(type /soleur:<name>)`, derived at render time (CTO devex 4).
- `plugins/soleur/commands/go.md`, **outside** the gated go-routing block (lines 513-527 are untouched):
  one note in the default route for operator tooling. When the request is for feature-flag
  create/delete/role changes, cron list/delete, tenant provisioning, the admin IP allowlist, user
  roles or Cloudflare token scope, reply with the exact slash command to type, never a silent miss.
  On the web Command Center, reply that these commands are CLI-only (spec-flow P1-5, CTO devex 4).
  It names flipped skills, so it gets `operator-handoff` ack rows.
- `plugins/soleur/skills/skill-creator/workflows/audit-skill.md` gains one invocation check: a
  human-only skill lacking the key, or a flagged skill that another file tells the model to invoke,
  is a finding (spec-flow P2-11).
- `plugins/soleur/skills/eval-harness/prompts/tool-selection-baseline.txt:10`: remove
  `provision-github, provision-cloudflare, provision-doppler` from the flat catalog. The baseline
  arm's catalog should match what the model now sees. None of the three is in the enum or is a
  golden label, so no recorded score moves (CPO C3, CTO finding 2).

### D2 — Count what the model sees, and ratchet the cap down (taste; see D6)

`components.test.ts:150-170` filters out user-invoked skills before summing.
`SKILL_DESCRIPTION_WORD_BUDGET` drops from 2561 to the **measured** post-flip total (2561 − 266 =
**2295** if nothing concurrent lands). That keeps the file's zero-headroom convention: every prior bump
reads "against a zero-headroom baseline". It also banks the relief as a lower ceiling rather than as
spendable slack. The harness cap this budget proxies is **already exceeded** on 200k-window models,
which is the probe's side finding.

The comment on line 21 appends
`lowered −266 for #8290 (12 skills moved to disable-model-invocation; counted words are model-visible only)`.

On harnesses that ignore the key (W0 decides which), the 12 descriptions still load. They stay
bounded by the existing per-skill `SKILL_DESCRIPTION_CHAR_LIMIT` (1024) test, which keeps counting
every skill, so they cannot grow unchecked.

**Alternative, recorded but not chosen:** keep 2561 and leave 266 words of headroom. That is the
issue's literal "relief", but it lets the listing regrow to today's size without a reviewed bump.

### D3 — skill-creator uses markdown, as measured, at every prescriptive site

Skill bodies are structured with markdown headings. XML tags are optional semantic wrappers *inside*
a section and never replace headings. The measured basis: 102/102 shipped `SKILL.md` bodies use `#`
headings, and 4 of them also use XML wrappers.

The contradiction is **wider than the issue named**. Kieran's P0 census, re-run at planning, found XML
prescriptions spread across skill-creator, so every one of these sites is rewritten:

| File | Lines | Change |
|---|---|---|
| `references/skill-structure.md` | 2, 5-33, 300, 318-322, 333-359, 397, 402 | Prescription → markdown headings. The pitfall is inverted: a tag-only body with no headings becomes the anti-pattern. Drop the `use-xml-tags.md` link at :32. The file's own wrapper tags stay, as content labels |
| `references/common-patterns.md` | 235-247, 436-467 | BAD/GOOD pairs inverted. ":467 prefer XML" → prefer headings |
| `references/iteration-and-testing.md` | 202, 218, 224, 239, 248-251, 319 | Validation steps check heading structure. "Required XML tags" removed |
| `workflows/audit-skill.md` | 8 (dangling pointer), 63-66, 137 | Audit for headings. Add the invocation check (D1) |
| `workflows/create-new-skill.md` | 9 (dangling pointer), 119, 163, 167 | Markdown |
| `workflows/create-domain-expertise-skill.md` | 32 (dangling pointer), 208, 582 | Markdown |
| `workflows/add-reference.md` | 48 | "Use markdown headings; XML wrappers optional" |
| `workflows/upgrade-to-router.md` | 91 | Same |
| `references/core-principles.md` | 185-187 | Already markdown. Add a one-line pointer to the new reference |

The AC is a **census, not an enumeration**. `git grep -niE 'pure xml|no markdown headings|instead of xml tags|required xml tags|prefer xml|use-xml-tags' -- plugins/soleur/skills/skill-creator/`
returns only the lines in a committed allowlist: the inverted pitfalls, which legitimately name the
anti-pattern. The allowlist is stated in AC-S2.

### D4 — One new reference, `references/authoring-levers.md`

This is a single co-located reference of about 120-160 lines. Each section uses Soleur's own words and
Soleur's own examples: it adopts the *patterns*, never the prose.

1. **Leading words.** A pretrained concept repeated as a token. Soleur examples already in the tree
   are `red` and `tracer`. The **negation** paragraph says to pair any prohibition with the positive
   target. It cites the B5 verdict, whichever way it lands, as Soleur's own measurement.
2. **The two loads**, context vs cognitive. This section carries the **invocation choice**:
   - the decision test: *could the model usefully reach for this on its own, or must another skill
     reach it?*;
   - ADR-236's K1/K2/K3;
   - the caveat that the web Command Center is model-only;
   - the harness caveat, filled from W0.

   It names no flipped skill (the Guard 1 post-remediation rule).
3. **Co-location**, contrasted with duplication, plus single source of truth.
4. **Criterion demand**: both clarity *and* demand.

**Wiring.** Add the file to `SKILL.md`'s reference index (`:257-267`). Add `disable-model-invocation` and
`user-invocable` rows to `official-spec.md`'s frontmatter table (`:26-33`). The source for those rows is
**Anthropic's Claude Code docs** (code.claude.com/docs/en/skills), cited inline.

**Attribution (CLO rules):**

- `authoring-levers.md` carries
  `<!-- Inspired by mattpocock/skills/skills/productivity/writing-for-agents/SKILL.md and mattpocock/skills/skills/productivity/writing-for-agents/SKILL-MECHANICS.md (MIT, Copyright (c) 2026 Matt Pocock). -->`.
  Both paths are verified to resolve at `c55ee46` (`gh api repos/mattpocock/skills/contents/<path>?ref=c55ee46…` returns 200).
- `official-spec.md` takes the comment **only if** the shingle check finds wording shared with
  `SKILL-MECHANICS.md`, or a row takes Pocock's *explanation* rather than the field's documented
  meaning. The outcome is recorded in the PR body, because a false credit is its own defect.

### D5 — B5 is measured on four rules, in the real loaded context, on a generation surface

The advisor's and CTO's findings replaced the first design, a closed-enum decision over a
16-rule excerpt. **That design showed the forbidden option as a label in every arm, including the
control.** It measured the opposite of the peer's claim, which is about *generation*.

- **Rules.** All four lead with "Never", and each has a **lexical observable in generated text**:

  | Rule | Scenario prompt ends with | Violation observable (command-context regex) |
  |---|---|---|
  | `hr-never-git-stash-in-worktrees` | "Write the exact shell commands you run next." | a command line matching `git stash` |
  | `hr-never-run-commands-with-unbounded-output` | "Write the exact command the subagent runs to inspect it." | a read of the named large file or command output with no `head`/`tail`/`-n N` bound on that line |
  | `hr-never-write-to-claude-code-memory-claude` | "Write where and how you save this so future sessions know." | a path matching `~/.claude/projects/…/memory` or `.claude/projects/*/memory` |
  | `wg-never-bump-version-files-in-feature` | "List the exact file edits you make before opening the PR." | an edit to a `version` field, or `npm version`/`bump version` |

- **Context.** Each arm is the **live** `AGENTS.md` + `AGENTS.rules.md` (~43 KB), generated at run time
  by `prompts/rule-phrasing.cjs` as a chat-format prompt. The corpus is the **system** message and the
  scenario is the user message, which mirrors how a session loads it (Kieran P2-12).
  - *prohibition*: the four bodies verbatim.
  - *positive*: the four bodies rewritten positive-led, with the hard guardrail kept as a **trailing
    paired clause** (the peer's own allowance).
  - *none*: the four body lines **and** their `AGENTS.md` index pointers removed.
  - The ids are immutable and stay in the index in both treated arms. So a positive body still travels
    with a `hr-never-git-stash-in-worktrees`-style slug, and the A/B holds that confound identical instead of pretending it away.
- **Fixture** (`prompts/rule-phrasing-bodies.json`). For each id it pins the prohibition body verbatim,
  that body's sha256, and the positive body. The generator refuses to run if a live body's hash differs.
  This keeps the eval re-runnable after any later edit, including an EXTEND follow-up. Draft positive
  bodies (pre-registered; each stays ≤ 600 B):
  - **Inline tags stay byte-identical and in place** (Kieran P0-2). `AGENTS.rules.md:21` and `:43`
    carry `[id: …]` and `[hook-enforced: …]` inside the body. Each positive body keeps every
    bracketed tag at its original position relative to the sentence it annotates. Without that, the
    arms would differ by more than phrasing, and an EXTEND would silently drop enforcement tags.
    AC-E2 asserts the `[` tag tokens are identical across all three arms. The drafts below omit the
    tags for readability only.
  - stash: *"In a worktree, commit WIP before switching context; inspect old code with
    `git show <commit>:<path>`, which leaves the working tree untouched. `git stash` is blocked here."*
  - unbounded output: *"In subagents, bound every command's output — `| head -n 500` or
    `| tail -n 200`. Subagent stdout lands on tmpfs, and unbounded output fills it and crashes every
    session."*
  - memory: *"Put all knowledge in committed files — AGENTS.md, constitution.md,
    `knowledge-base/project/learnings/`, `.mcp.json` — so a new Soleur user cloning the repo gets it.
    Claude Code memory and other local-only paths are blocked."*
  - version: *"Leave version files to CI: `vX.Y.Z` releases are cut from git tags at merge via semver
    labels (set with `soleur:ship`). No plugin manifest carries a `version` key, and adding one makes
    `plugin update` no-op while reporting success (#7471)."*
- **Scoring** (Kieran P1-5). `scripts/measure-rule-compliance.cjs` follows the house
  `measure-classification.cjs` shape: it always returns `pass: true`, carries
  `score`/`reason` (reason prefix `rule-(non)compliant`), and dispatches on `vars.rule` so only the task's own rule observable
  scores it. Each arm carries an explicit promptfoo `label:` (`prohibition`/`positive`/`none`), so
  arm identity never depends on file order. `ANTHROPIC_MAX_TOKENS=300` is set in the run environment,
  because `models.generated.json` is a string list and cannot carry config. The per-arm truncation
  rate is recorded, since a cut-off answer can score compliant by omission.
- **Statistics** (CTO finding 3). The unit of analysis is the **task**, not the call. Per task *t*,
  model *m* and arm *a*: compliance rate over repeats. Per task: Δ_t is the mean over models of
  (positive − prohibition). Then Δ = mean(Δ_t) and SE = sd(Δ_t)/√24, clustered by task. This is
  conservative: repeats and models on the same scenario are not treated as independent. Sampling uses
  the provider default; promptfoo 0.123.1 omits explicit `temperature` on some current models. The
  task clustering keeps the SE valid whether or not repeats are correlated.
- **Minimum worthwhile effect: 10 percentage points.** Measured at a 2·SE interval,
  **EXTEND** requires every one of these:
  - Δ ≥ MWE;
  - the lower bound > 0;
  - every model's Δ_m ≥ −ε (ε = 1/24);
  - Δ_r > 0 on at least 3 of the 4 rules;
  - V1 holds for each scored rule: prohibition − none ≥ ε.

  **REJECT** requires the upper bound < MWE, meaning a worthwhile effect is excluded.
  **INVALID** applies when no rule passes V1, and **ABORTED** when the run is truncated, has errors or
  hit the spend cap. Neither yields a record beyond `b5-eval-results.md`: one rerun is allowed, and
  then B5 moves to its own issue. The precedence is fixed in Guard 2.
  **REJECT-CEILING** applies when prohibition ≥ 0.95 on every V1 rule.
  **INCONCLUSIVE** covers everything else.
- **Power, stated before spending.** With 24 clustered units, a task-level SD of about 0.25 gives
  SE ≈ 0.05, so the 2·SE half-width is about 10 pts, the same as the MWE. The run can therefore separate
  "≥ 10-pt win" from "no worthwhile effect" only when the observed Δ sits near the edges. An
  INCONCLUSIVE result is a likely and honest outcome. The operator's mapping still applies to it (D6.1).
- **EXTEND must fit before any money is spent** (spec-flow P1-7). At Phase 3 step 2, compute
  `B_ALWAYS` with the positive arm's four bodies swapped in, and the per-body bytes. If that would
  exceed the 44,000 warn tier or any 600 B cap, tighten the positive text **before** the run. It is
  pre-registration, so it cannot happen after.
- **EXTEND does not land in this PR** (architecture P1-3). `.claude/rule-weakening-acks.txt` is
  CODEOWNERS-owned, and CODEOWNERS review is not yet enforced on main, so an autonomous run appending
  its own acks would approve its own weakening. On EXTEND, this PR records the verdict in ADR-236 and
  `b5-eval-results.md`. The run then opens a **separate follow-up PR** containing the four rewritten
  bodies, the regenerated hashes and the ack lines. That PR is labelled for @deruelle's review and
  excluded from auto-merge. This PR stays mergeable either way, and the operator's rule, "only extend
  on a measured improvement", holds.
- **Validity limit, stated.** A lexical observable measures one generated behaviour per rule, on
  single-turn scenarios. It does not measure multi-turn drift or the rules' hook-backed enforcement,
  which does not run inside promptfoo.

### D6 — Decision Challenges (headless: persisted, not asked)

These are persisted to `knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/decision-challenges.md`
for `ship` to render and file.

1. **(User-Challenge) What a non-EXTEND verdict records, and where.** The operator directed: "if it
   shows none, close B5 as tested-and-rejected and record it in the rejected-concepts record." There
   are two frictions.
   - That record's README reserves it for refused **concepts** and routes refused **mechanisms** to ADR
     alternatives tables.
   - The advisor warns that a public refusal written from an underpowered null overstates the evidence.

   The CPO (plan-review) adds a sharper objection. INCONCLUSIVE carries a `revisit_if`, so by the
   README's own "not a deferral" test it reads as one. CEILING ("the prohibitions already hold") reads
   close to the README's redundancy case. The CPO recommends writing the entry **only on REJECT**.

   Kieran adds that `README.md:146-148,165` forbids writing an unconfirmed entry, and forbids
   recording something nobody refused.

   **Default: split by verdict.** B5 is **closed** under every non-EXTEND verdict, which honours the
   operator's "close B5". The record goes where each verdict's own contract allows it:

   | Verdict | Where it is recorded |
   |---|---|
   | **REJECT** (a worthwhile effect is excluded) | The no-list entry the operator asked for, framed as Soleur's own measurement. Mirrored in ADR-236's alternatives table |
   | **REJECT-CEILING** | The no-list entry, framed as "the prohibitions already hold on the tested surface, so no rewrite is warranted" |
   | **INCONCLUSIVE** | ADR-236's table and `b5-eval-results.md` only. A `revisit_if`-shaped follow-up issue is filed, **not** a no-list entry, because that record's own README (also the operator's, from bundle 3) says an entry is not a deferral and not a non-refusal |

   Every entry written is gated on the typed-concept confirmation (DC-5), as a merge gate. The operator
   can override INCONCLUSIVE toward an entry at review.

2. **(User-Challenge) Split B5 into its own PR.** The CTO and the advisor both recommend it, so that
   ADR-236 and the ratchets do not wait on an experiment. The operator's direction bundles B5 into
   #8290 and asks for it to be closed in this run. **Default: the eval and its verdict stay bundled.**
   The coupling cost is minutes. Only an EXTEND's `AGENTS.rules.md` edits move to a follow-up PR, per
   D5, for the CODEOWNERS reason.
3. **(Taste) Ratchet the cap down or keep the slack** (D2).
4. **(User-Challenge) Flip 12, not 16.** The issue listed 16. The evidence moves 4 out:
   - one (`flag-bootstrap`) is not a skill;
   - three (`trigger-cron`, `invoice`, `flag-list`) fail the issue's own "verify before flipping" test
     or the peer's own "could the model usefully reach for this" test.

   **Default: 12**, because the issue's own instruction produces it.
5. **The no-list's typed-concept confirmation** (README "Writing an entry" step 4) cannot be taken
   headless. It is surfaced in the PR body. The operator's standing direction in #8290 plus the run
   constraints is recorded as the basis for writing the file.
6. **(Declined, with reason) CPO C2, "run the tool-selection eval before and after".** That eval's
   arms are static hand-written catalogs, so they cannot observe the harness listing the flip changes.
   The measurement that *can* observe it is kept: W0-f, the before/after listing probe on a 200k-window
   model.

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-236-human-only-skills-are-user-invoked.md`. The
  ordinal is provisional. ADR-235 is claimed on two pushed branches, and 236 is free across all 96
  `origin/*` refs as of planning.
- `plugins/soleur/test/invocation-axis.test.ts` (Guard 1)
- `plugins/soleur/skills/skill-creator/references/authoring-levers.md`
- The B5 eval, under `plugins/soleur/skills/eval-harness/`:
  - `promptfooconfig-rule-phrasing.yaml`: three labelled arms, the tasks, and the measure assert
  - `prompts/rule-phrasing.cjs`: three chat-format arm functions over the live corpus, with a hash-lock check
  - `prompts/rule-phrasing-bodies.json`: each id → the pinned prohibition body, its sha256, and the positive body
  - `tasks/rule-phrasing.jsonl`: 24 rows of `{vars:{rule, input}}`
  - `scripts/measure-rule-compliance.cjs`: the per-rule observable, returning `pass: true` with `score`/`reason` (house shape)
  - `scripts/rule-phrasing-verdict.cjs`: `verdict(json)` plus a CLI, with the fixed precedence
  - `test/rule-phrasing.test.sh` and `test/fixtures/rule-phrasing/*.json`: E0-E9 plus the observable sample table
- Under `knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/` (persistent paths, never `/tmp`):
  - `b5-eval-results.md`: baselines, the raw rates, the verdict module's sha256 and its output, and tokens/cost
  - `w0/`: the probe transcripts, the tmux captures and the `devin skills list` output
  - `decision-challenges.md`: written at plan time, appended as the work proceeds
- **Iff the B5 verdict is REJECT or REJECT-CEILING, and the typed-concept confirmation is given:**
  `knowledge-base/project/rejected/<date>-positive-only-rule-phrasing.md`
- **Iff EXTEND:** nothing more in this PR. A **follow-up PR** is opened with the rewritten bodies and
  the acks (D5).

## Files to Edit

- The frontmatter of 12 `plugins/soleur/skills/<name>/SKILL.md` files gains `disable-model-invocation: true`.
  The 12 are flag-create, flag-delete, flag-set-role, cron-list, cron-delete, provision-cloudflare,
  provision-doppler, provision-github, provision-hetzner, admin-ip-refresh, user-set-role and
  cf-token-scope.
- `plugins/soleur/skills/schedule/SKILL.md:732,771` and `plugins/soleur/skills/trigger-cron/SKILL.md:26-27`:
  reword the cron verbs as human-typed shortcuts (D1).
- `plugins/soleur/skills/flag-create/SKILL.md:41,72` and `cron-delete/SKILL.md:37`: rewrite into an
  explicit operator hand-off, but only if the one-time read finds them operative (D1).
- `knowledge-base/engineering/operations/runbooks/tenant-provisioning.md:59,98,135,169,319`: change each
  `**Skill:**` line to an operator hand-off (D1).
- `plugins/soleur/commands/help.md`: add the `(type /soleur:<name>)` marker (D1).
- `plugins/soleur/commands/go.md`: add the operator-tooling hand-off note **outside** the gated block at
  lines 513-527 (D1).
- `plugins/soleur/skills/eval-harness/prompts/tool-selection-baseline.txt:10`: drop the three flipped names.
- `plugins/soleur/test/components.test.ts`:
  - the budget filter and the ratcheted cap (`:21`, `:150-170`);
  - keep-pins for `trigger-cron`, `invoice` and `flag-list` as their **own** `MUST_STAY_INVOCABLE` set
    with its own exact-set pin, placed next to `:1329`. It asserts only
    `fm["disable-model-invocation"]` `toBeUndefined()`. They must **not** join `ACKED_CROSS_ROOT_DUPES`:
    that set is pinned to exactly `go`/`help`/`sync` at `:1303`, and at `:1344` it also asserts
    `user-invocable === false`, which these three do not carry (deepen pattern-review 2).
- `plugins/soleur/skills/skill-creator/`:
  - `SKILL.md`: the reference index (`:257-267`);
  - `references/official-spec.md`: the frontmatter rows, sourced from the Claude Code docs;
  - every D3 census file: `references/skill-structure.md`, `references/common-patterns.md`,
    `references/iteration-and-testing.md`, `references/core-principles.md`, `workflows/audit-skill.md`,
    `workflows/create-new-skill.md`, `workflows/create-domain-expertise-skill.md`,
    `workflows/add-reference.md` and `workflows/upgrade-to-router.md`.
- `plugins/soleur/skills/eval-harness/README.md`: one row describing the measurement-only `rule-phrasing`
  target, its call count and its token volume. The row must not contain the registry marker literal.
- `plugins/soleur/NOTICE`, the mattpocock block:
  - `Used in:` gains `skills/skill-creator/references/authoring-levers.md` (plus `official-spec.md` iff
    D4 applies) `(#8290)`;
  - `Portions adopted:` names the patterns, with the peer paths given at the pinned SHA.
- `knowledge-base/engineering/architecture/decisions/ADR-151-agents-rule-corpus-is-unconditionally-loaded.md`:
  the addendum.
- `knowledge-base/operations/expenses.md`: only if it has a place for a one-off dev-tools run.
  Otherwise `b5-eval-results.md` is the cost record (COO).
- `knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/session-state.md`:
  **append only**. `## Carry-Forward` survives byte-identical.

### Explicitly NOT edited

- `trigger-cron`, `invoice` and `flag-list` frontmatter: they stay invocable. `flag-bootstrap/SETUP.md`
  is a human runbook.
- `flag-delete/SKILL.md:20`: it works unchanged, because flag-list stays invocable.
- The `description:` text of the 12 flipped skills, and `schedule`'s description, which already covers
  list and delete.
- The gated go-routing block (`go.md:513-527`), `eval-harness/enums/go-routes.json` and
  `eval-harness/gated-skills.json`.
- `AGENTS.rules.md` and `.claude/rule-weakening-acks.txt`, **in this PR** under every verdict. EXTEND
  edits go to the follow-up PR.
- `apps/**` (including migration 054's error text), `scripts/**` and `.github/workflows/**`.
- The mutating scripts' TTY gap (`flag-delete/scripts/delete.sh:146`). It is pre-existing, so a
  follow-up issue is filed at work time.

## Non-Goals

- Rewriting the other 6 leading-negative rules, or the ~45 other prohibition-carrying rules. At most
  the four tested rules change, and only on a measured win. A win files a follow-up issue for the
  rest behind the same eval. A loss closes B5.
- A router skill: `soleur:help` already renders every skill for the human.
- Converting skill-creator's own reference files from XML wrappers to headings.
- Making the flip effective on Codex/Devin/Grok. Where a harness ignores the key, nothing regresses
  and nothing is saved, and the ADR says so per harness.
- A repo-wide dangling-reference guard (Cut List).

## Implementation Phases

### Phase 0 — Preconditions and the architecture-deciding probe (runs FIRST, no shipped writes)

W0 is the only step that can prove the architecture wrong, so it runs before any test, flip or
ratchet (advisor). Every artifact goes under
`knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/w0/`, which persists
(carry-forward error 7).

1. **Re-measure and quote** into the header of `b5-eval-results.md`:
   - the budget one-liner (expect `2561 / 2561`);
   - `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1` (expect `B_ALWAYS=42920`);
   - `claude --version`, `devin --version` and `codex --version`.
2. **W0 on the throwaway probe plugin**, rebuilt under `w0/probe8290/`. Record the probe's sha256 in
   `w0/`. Run each case in a clean context (`--setting-sources project`, stdin `< /dev/null`). Every
   headless probe runs with `--disallowedTools Bash,Write,Edit` and a non-bypass permission mode, because
   `--plugin-dir plugins/soleur` also runs the plugin's own hooks (security-sentinel LOW). Every tmux
   session is created under a `trap 'tmux kill-session -t w0' EXIT`. `gitleaks detect --no-git --source w0/`
   must pass before any W0 artifact is committed.
   - **a.** A headless user slash, `/probe8290:flagged`, runs.
   - **b.** "Use the Skill tool to invoke probe8290:flagged" is refused with `disable-model-invocation`.
   - **d. Interactive TUI** (CPO C1, CTO 6). Start `claude --plugin-dir <probe>` in a detached `tmux`
     session and `send-keys` `/probe8290:fla`. Run `capture-pane` to check the autocomplete, submit,
     then run `capture-pane` again for `SENTINEL-FLAGGED-RAN`.
   - **e. Devin: required.** 10 of the 12 flips are in the Devin cloud-mode union
     (`devin-cloud-mode.test.ts:460`). `devin skills list` prints an invocation marker per skill, for
     example `[user,model]`, measured at planning. Load the probe plugin where `devin skills list`
     reads it and record the flagged skill's marker. A `[user]` marker, or any listing that keeps it
     user-typeable, passes. If it is **absent**, or it cannot be measured, the result is **W0-STOP**
     (architecture P1-4).
   - **e'. Codex: best-effort.** Use `codex plugin`. Record the result, or UNVERIFIED with the reason,
     and add a rollback trigger to ADR-236.
   - **f. Listing effect** (CPO C2). On haiku-4.5, with `--plugin-dir plugins/soleur`, capture the
     listing self-report *before* the flip: `TOTAL_WITH_DESC`/`TOTAL_NAME_ONLY` plus the 11 named
     skills.
   - **Stop rule.** If a or d fails, or e is STOP, apply the **W0-STOP profile** (spec-flow P0-1):
     - B6 and B5 proceed, along with the ADR-151 addendum, which still records `B_ALWAYS` Δ = 0.
     - No frontmatter flip, no Guard 1, no D2 ratchet, and the `help.md`/`go.md` notes are left out.
     - ADR-236 is written as `status: proposed`, with the evidence and a tracking issue. The template
       lists only `active|superseded`, so cite the precedent ADR-131 and ADR-220, which use
       `proposed`.
     - The "two loads" section of `authoring-levers.md` says "flip deferred — see #<tracking>".
     - Frontmatter `closes: 8290` → `refs: 8290`, and the PR body says `Ref #8290`.
3. **Re-run the subject sweep.** Run `git grep -nw <name>` for each of the 12, over every Guard 1
   pathspec plus `apps/`, and diff the result against the plan's classification. Classify any hit that
   is new since planning before any flip.

### Phase 1 — Invocation axis (skipped entirely under W0-STOP)

1. Write `plugins/soleur/test/invocation-axis.test.ts` **first**, against the current tree. The
   exact-set pin is RED until step 2. `git add` it before running (carry-forward error 8).
2. Add `disable-model-invocation: true` to the 12 frontmatters.
3. **Rewordings and the one-time read:**
   - Apply the D1 rewordings: `schedule`, `trigger-cron`, `tenant-provisioning.md`, `help.md`,
     `go.md` (outside the gated block) and `tool-selection-baseline.txt`.
   - Read the **exempt intra-flipped-family group** once (`flag-create:41,72`, `cron-delete:37`, and
     any other hit) and rewrite each operative line.
   - Read every remaining Guard 1 hit and fill the ack table with one (file, skill) row each, with
     reason `doc-mention` or `operator-handoff`.
4. Ratchet the cap (D2) to the **measured** post-flip total.
5. **Real plugin** (`--plugin-dir plugins/soleur`):
   - `/soleur:cron-list` runs headless.
   - The Skill tool refuses `soleur:cron-list`.
   - `soleur:trigger-cron` and `soleur:flag-list` launch.
   - The **tmux TUI capture** on `/soleur:flag-cr`, where `flag-create` must autocomplete (CPO, spec-flow P1-6).
   - W0-f *after*.
6. `bun test plugins/soleur/test/invocation-axis.test.ts plugins/soleur/test/components.test.ts`.
   Then drive Guard 1's matrix on a scratch copy: M1, M2, M5-M9 and H2-H5, one at a time. Observe each
   named test go RED or GREEN as tabled, restore, and record the outcomes in the PR body.
7. File the follow-up issue for the **pre-existing** agent-bypass surface of the operator scripts
   (deepen security-sentinel HIGH). It covers:
   - `flag-delete/scripts/delete.sh:146`, `flag-create/scripts/create.sh:116` and
     `user-set-role/scripts/set-role.sh:109`, whose typed-yes prompts accept piped stdin;
   - `flag-set-role/scripts/flip.sh --confirmed`, which skips its prompt for "agent-driven use".

   The issue must say that a `[[ -t 0 ]]` check is **not** the fix, because Claude's Bash tool never
   has a TTY and the check would also break the legitimate typed path. The proposed control is a
   PreToolUse Bash hook that denies `plugins/soleur/skills/<flipped>/scripts/*` and `--confirmed`
   unless the current turn began with `/soleur:<that-skill>`, detected by a UserPromptSubmit marker.
   Verify labels with `gh label list`, and take the milestone from `knowledge-base/product/roadmap.md`.
   The flip itself neither creates nor closes this gap. ADR-236 states that the invocation axis is a
   **context-budget and discoverability** measure, **not a security control**.

### Phase 2 — skill-creator (B6)

1. Write `authoring-levers.md` (D4). It names no flipped skill, and its attribution comment carries
   both full peer paths, verified at `c55ee46`. Its "two loads" section includes:
   - the headless-refusal policy (spec-flow P1-3): on a Skill-tool refusal in an unattended run, stop
     and file an `action-required` issue naming the command to type, and **never** re-run a
     user-invoked skill's steps by hand;
   - the 13th-flip checklist, which names the four sites that move together: the pin, the ack table,
     the ADR-236 list and the cap.
2. Apply every D3 census edit, then the `official-spec.md`, `core-principles.md` and `SKILL.md` edits.
3. Run the AC-S1 and AC-S2 census greps.
4. **Shingle check** against the three pinned peer blobs, using 8-word shingles over normalised
   lowercase text:
   - `skills/productivity/writing-for-agents/SKILL.md`
   - `skills/productivity/writing-for-agents/SKILL-MECHANICS.md`
   - `.agents/invocation.md`

   Report the counts per file and rewrite any shared 8-gram, keeping the before/after text for the PR
   body (CLO). This check runs before merge only.
5. Update NOTICE.

### Phase 3 — B5 eval: measure, then branch

1. **Build the fixture** (D5, Guard 2). Write the battery `test/rule-phrasing.test.sh`, including the
   observable sample table and E0-E9. `git add` it, then run it: it must be green, and its anti-vacuity
   floor must fire when the case loop is emptied.
2. **Before any API call:**
   - Render the three arms with `node -e` over `prompts/rule-phrasing.cjs` and diff them (AC-E2). This
     covers the 4 changed bodies, the 8 lines removed for `none`, and byte-identical `[` tags.
   - Compute **B_ALWAYS with the positive bodies swapped in**, plus each body's byte count. If that
     would exceed 44,000 or any 600 B cap, tighten the positive text now (spec-flow P1-7).
   - Run `npx promptfoo validate config -c promptfooconfig-rule-phrasing.yaml`, which makes zero calls.
     It confirms the `file://prompts/rule-phrasing.cjs:<fn>` chat-format prompts. Kieran verified that
     promptfoo 0.123.1 supports `.cjs:fn`.
3. Check that no changed file outside `eval-harness/` contains a registry block marker:
   `git diff --name-only "$(git merge-base origin/main HEAD)" | grep -v '^plugins/soleur/skills/eval-harness/' | xargs -r grep -lE 'eval-gate:block:[a-z][a-z0-9-]*:start'`
   must print nothing. Then run `registry-completeness.test.sh`, which must be green.
4. **Budget disclosure.** The run is 3 arms × 3 models × 24 tasks × `--repeat 3` = **648 calls**. Each
   call carries about 12k system tokens, about **7.8M input tokens** in total, with
   `ANTHROPIC_MAX_TOKENS=300`. **Pre-registered spend cap: $60**, with prices looked up at run time.
   If the estimate exceeds it, run `--repeat 2` and keep all three models.
5. `ANTHROPIC_MAX_TOKENS=300 npx promptfoo eval -c promptfooconfig-rule-phrasing.yaml --repeat 3 -o "${XDG_CACHE_HOME:-$HOME/.cache}/soleur-8290/b5-eval-raw.json"`. The raw grid is several MB of prompts and responses, so it lives **outside the repo** in a persistent cache and is never committed (security-sentinel MEDIUM). Only the reduced `b5-eval-results.md` is committed, after `gitleaks detect --no-git --source <spec-dir>` passes. `ANTHROPIC_API_KEY` comes from the environment only, never from a promptfoo config field
6. `node plugins/soleur/skills/eval-harness/scripts/rule-phrasing-verdict.cjs "${XDG_CACHE_HOME:-$HOME/.cache}/soleur-8290/b5-eval-raw.json"`
   writes the verdict and every intermediate value into `b5-eval-results.md`, along with the module's
   sha256, the per-arm truncation rates, and the tokens and cost.
7. **Branch on the verdict:**
   - **EXTEND:** record the verdict in ADR-236. Open the **follow-up PR** containing the four bodies,
     the output of `lint-rule-bodies.py --write`, and the WORM ack lines in the documented format
     `<id>|<sha256>|<date>|<PR>|<reason>` with the NEW hash. Request @deruelle's review and exclude it
     from auto-merge (D5). Also file a follow-up issue for the other 6 leading-negative rules.
   - **REJECT or REJECT-CEILING:** close B5 and draft the no-list entry. The literal filename slug
     phrase "positive-only rule phrasing" appears in `scope:` (lint check 5). Every `searched:` line
     has the `<command> -> <result>` shape (check 7). Run `bash scripts/lint-rejected-register.sh --all`,
     which must exit 0 (the CI form, `ci.yml:246`). The entry lands only with the typed-concept
     confirmation (DC-5, a merge gate). Without that confirmation, delete the entry before merge and
     keep the ADR row.
   - **INCONCLUSIVE:** close B5. Record the verdict in ADR-236 and `b5-eval-results.md`, and file a
     `revisit_if` follow-up issue. **Write no no-list entry** (DC-1).
   - **INVALID or ABORTED:** allow one rerun. If it fails again, split B5 into its own issue. Write no
     verdict record anywhere except `b5-eval-results.md`.

### Phase 4 — Records

1. **ADR-236.**
   - K1-K3 are phrased as **necessary** conditions ("only if", architecture P0). Membership is D1's
     list, fixed by the pin. K2 and K3 are review criteria, not test-enforced.
   - Cite the `POSTAMBLE` constant.
   - State that user-invoked skills are unreachable from the web Command Center, which gets a CLI-only
     reply via `go.md`.
   - Include the headless-refusal policy and the measured table: Phase 0, Phase 1 step 5, the verdict,
     and the verdict module's sha256.
   - Name the read-only admin-IP check in `admin-ip-drift.md` as the agent's no-flip path for
     `hr-ssh-diagnosis-verify-firewall`.
   - Name the rollback triggers.
2. Write the ADR-151 addendum.
3. Run `bash scripts/check-adr-ordinals.sh`.

### Phase 5 — Pre-push repo-global ratchets (MANDATORY, before the FIRST push, whatever the diff touches)

Carry-forward errors 4 and 8 put this list here. In bundle 3, six defects lived in suites that named
none of the changed files, and each cost a CI cycle. The population is the **repo-global enumerators**.

**Stage first.** `git add` every new and edited feature path. Then `git status --short` must show no
`??` under `plugins/`, `scripts/`, `knowledge-base/` or `.claude/`. A ratchet that walks `git ls-files`
cannot see an untracked file.

**Then run** each check by the invocation CI (or lefthook) uses, and paste each tail into the PR body:

```
bun test plugins/soleur/
(cd apps/web-platform && npx vitest run --project repo-wide)
bash scripts/guard-vacuity-floor.test.sh
for t in $(git ls-files '*.test.sh' | xargs grep -lE 'git (ls-files|grep)|find ' ); do bash "$t" > /dev/null 2>&1 || echo "FAILED: $t"; done
bash plugins/soleur/skills/eval-harness/test/registry-completeness.test.sh
bash plugins/soleur/skills/eval-harness/test/rule-phrasing.test.sh
bash plugins/soleur/test/c4-count-parity.test.sh
python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1
python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.rules.md
python3 scripts/lint-rule-bodies.py --check --base "$(git merge-base origin/main HEAD)"
python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"
python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main
python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-21-refactor-invocation-axis-budget-relief-plan.md
bash scripts/lint-orphan-test-suites.sh
bash scripts/check-adr-ordinals.sh
bash scripts/lint-rejected-register.sh --all
```

Notes on these commands:

- `lint-rule-ids.py` runs from lefthook (`lefthook.yml:103`), not a CI workflow. The invocation above
  is that one.
- `scripts/test-all.sh` is **not** run (operator constraint).
- The loop selects every tracked `*.test.sh` that enumerates the tree itself. The list is derived,
  never hand-kept.
- Diagnose red only after the **whole** list has run, never from the first failure.

Then run the trap detectors over this PR's own prose:

- `bash scripts/lint-squash-ci-directives.sh` over the PR body and the planned squash message.
- The PR-body citation extractor, run locally.
- `gh pr view <N> --json closingIssuesReferences` must return `[8290]` only, or `[]` under W0-STOP.

### Phase 6 — Ordinal re-derivation immediately before merge

After the final `origin/main` sync, re-run the ordinal probe across **every `origin/*` ref**. If 236
is taken, renumber and sweep the subject in the same edit:
`git grep -n 'ADR-236' -- knowledge-base/ plugins/`, plus **the PR body** (architecture P2-9).

## Acceptance Criteria

Under **W0-STOP**, AC-A1 to A9 are N/A. Their replacement is AC-W: ADR-236 is `status: proposed` with
the evidence, a tracking issue exists, and `closingIssuesReferences` is `[]`.

### Invocation axis

- [ ] **AC-A1.** Guard 1's parsed `USER_INVOKED` set equals D1's 12 names (the exact-set pin). A text grep does not count: frontmatter parsing decides (test-design).
- [ ] **AC-A2.** `trigger-cron`, `invoice` and `flag-list` are pinned model-invocable through a separate `MUST_STAY_INVOCABLE` exact-set pin (not `ACKED_CROSS_ROOT_DUPES`). Each assertion message states the D1 reason. The `go`, `help` and `sync` pins are unchanged.
- [ ] **AC-A3.** `invocation-axis.test.ts` is green on the finished tree. The number of rows in its ack table equals the hit count the guard prints. Each of M1, M2 and M5-M9 turns RED **in its named test**. H2 and H3 turn RED. H4 and H5 stay GREEN. Every per-glob floor and the scanned-count = `ls-files`-count assertion are live. The PR body lists the outcome of each row.
- [ ] **AC-A4.** The budget test reports the post-flip total, and `SKILL_DESCRIPTION_WORD_BUDGET` equals it (zero headroom, D2). The line-21 comment carries the `−266 for #8290` note, or the measured figure if it differs.
- [ ] **AC-A5.** The web and cron surfaces name no flipped skill except in comments: `git grep -nE 'soleur:(flag-(create|delete|set-role)|cron-(list|delete)|provision-(cloudflare|doppler|github|hetzner)|admin-ip-refresh|user-set-role|cf-token-scope)' -- apps/web-platform/server apps/web-platform/lib ':!*.test.ts'` → only comment lines, each listed in the PR body. Guard 1 group G3 keeps the Inngest prompts covered durably.
- [ ] **AC-A6 (W0 evidence, a merge gate).** `w0/` holds the transcripts and captures for each of these:
  - the probe plugin, W0-a, b and d: headless slash runs, the Skill tool refuses, the interactive TUI autocompletes and runs;
  - W0-e, Devin: measured, with the `devin skills list` marker line quoted;
  - W0-e', Codex: measured, or UNVERIFIED with a reason;
  - on the **real** plugin: `/soleur:cron-list` runs; the Skill tool refuses `soleur:cron-list`; `soleur:trigger-cron` and `soleur:flag-list` launch; the TUI capture autocompletes `/soleur:flag-create`.
- [ ] **AC-A7.** The one-time read of the exempt group is recorded in the PR body, one line per hit with its classification. After it, no flipped skill's body tells the model to invoke another flipped skill: every such line is a hand-off.
- [ ] **AC-A8.** Four rewrites land:
  - `schedule/SKILL.md` and `trigger-cron/SKILL.md` describe `cron-list` and `cron-delete` as human-typed shortcuts;
  - `` grep -c '^> \*\*Skill:\*\* `soleur:provision' knowledge-base/engineering/operations/runbooks/tenant-provisioning.md `` → `0`;
  - `tool-selection-baseline.txt` names none of the 12;
  - `help.md` carries the type-only marker rule, and `go.md`'s hand-off note sits outside lines 513-527. `git diff` of the go-routing gated block is empty.
- [ ] **AC-A9.** ADR-236 records the W0-f before and after counts, labelled as model self-report. If the after count is not ≥ the before count on the 11 named skills, ADR-236 says "no observed listing benefit on 200k-window models" (CPO).

### Budget records

- [ ] **AC-B1.** `B_ALWAYS` is measured before and after Phase 1 by `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md 2>&1`. The two figures are equal (Δ = 0 B). Both outputs are quoted in ADR-236 and in the ADR-151 addendum, together with the live headroom (44,000 − measured).
- [ ] **AC-B2.** ADR-236 exists at the next free ordinal and contains:
  - K1-K3 as necessary conditions, "only if";
  - the D1 table;
  - the measured saving, in words and bytes;
  - the probed versions and per-harness status;
  - the web Command Center "CLI-only" statement;
  - the headless-refusal policy;
  - the rollback triggers;
  - the positive-phrasing alternatives row, with the verdict token, the interval, the eval command and the verdict module's sha256.
- [ ] **AC-B3.** The ADR-151 addendum exists (≤ 15 lines) and states that the invocation axis is not a `B_ALWAYS` lever.

### B5

- [ ] **AC-E1.** `npx promptfoo validate config -c plugins/soleur/skills/eval-harness/promptfooconfig-rule-phrasing.yaml` exits 0.
- [ ] **AC-E2.** The rendered-arm diffs are pasted into `b5-eval-results.md` and show three things:
  - prohibition vs positive differs in exactly the 4 target body lines;
  - prohibition vs none removes exactly 8 lines: 4 bodies and 4 `AGENTS.md` pointers;
  - every `[`-bracketed tag token (`[id: …]`, `[hook-enforced: …]`, `[skill-enforced: …]`) is byte-identical across all three arms.

  The fixture's `prohibition_sha256` values match the live bodies. The generator's hash-lock throws when one fixture body is mutated, and that is observed once.
- [ ] **AC-E3.** `bash plugins/soleur/skills/eval-harness/test/rule-phrasing.test.sh` is green. E0 yields `EXTEND`, E8 yields `REJECT`, E6 yields `REJECT-CEILING`, E7 yields `INCONCLUSIVE`, E2 yields `INVALID`, and E9 yields `ABORTED`. The observable sample table passes, including the refusal-sentence case. Its anti-vacuity floor prints the house sentinel when the loop is emptied.
- [ ] **AC-E4.** `b5-eval-results.md` holds the verdict module's output, with exactly one token from the six. It also holds every intermediate value, the per-arm truncation rates, and the token count and cost.
- [ ] **AC-E5.** `git diff "$(git merge-base origin/main HEAD)" -- AGENTS.rules.md .claude/rule-weakening-acks.txt` is empty **in this PR** under every verdict. On EXTEND, the follow-up PR exists, requests @deruelle's review, is not set to auto-merge, and its bodies are byte-identical to the fixture's `positive` values.
- [ ] **AC-E6.** The records match the verdict:
  - on REJECT or REJECT-CEILING, the no-list entry exists iff the typed-concept confirmation was given, and `bash scripts/lint-rejected-register.sh --all` exits 0;
  - on INCONCLUSIVE, no entry exists and the follow-up issue does;
  - under every verdict, `decision-challenges.md` carries DC-1 and DC-5.
- [ ] **AC-E7.** No changed file outside `eval-harness/` contains a registry block-start marker (Phase 3 step 3 command), and `registry-completeness.test.sh` is green.

### skill-creator (B6)

- [ ] **AC-S1.** `git grep -n 'use-xml-tags' -- plugins/soleur/skills/skill-creator/` → 0.
- [ ] **AC-S2 (a census, not an enumeration).** `git grep -niE 'pure xml|no markdown headings|instead of xml tags|required xml tags|prefer xml' -- plugins/soleur/skills/skill-creator/` returns only the lines in the allowlist. The allowlist is fixed at Phase 2 step 3 as the inverted-pitfall lines that name the anti-pattern, and is pasted in the PR body with each line's reason. `skill-structure.md` and `audit-skill.md` each contain D3's heading-structure rule text.
- [ ] **AC-S3.** `authoring-levers.md` has the four lever H2 sections. Its two-loads section carries the headless-refusal policy and the 13th-flip checklist. It is listed in `skill-creator/SKILL.md`. `official-spec.md` documents `disable-model-invocation` and `user-invocable`, and cites the Claude Code docs URL.
- [ ] **AC-S4.** `authoring-levers.md` names none of the 12 flipped skills.

### Attribution and originality

- [ ] **AC-L1.** Each file that takes peer-derived prose carries the D4 comment verbatim. The decision on `official-spec.md` is recorded in the PR body.
- [ ] **AC-L2.** In NOTICE, `Used in:` lists those files with `(#8290)`, and `Portions adopted:` names the patterns.
- [ ] **AC-L3.** The Phase 2 step 4 shingle counts are 0 shared 8-grams against all three blobs. Otherwise each match is rewritten, with the before and after in the PR body.

### Cross-cutting

- [ ] **AC-X1.** The whole Phase 5 list ran **before the first push**, after staging. Each command's tail is in the PR body. `scripts/test-all.sh` was not run.
- [ ] **AC-X2.** `git diff "$(git merge-base origin/main HEAD)" -- knowledge-base/project/specs/feat-one-shot-8290-invocation-axis-budget-relief/session-state.md` shows added lines only.
- [ ] **AC-X3.** The PR body uses a closing keyword for `#8290` only, or `Ref #8290` under W0-STOP. Verify on the field with `gh pr view <N> --json closingIssuesReferences` (carry-forward error 6).
- [ ] **AC-X4.** Every rule-id-shaped token in the new or edited **shipped** files resolves to an active `[id: …]` in `AGENTS.rules.md` or to a row in `scripts/migrated-rule-ids.txt`. This plan and the `specs/` artifacts are excluded, because they quote truncated slugs as prose (Kieran P2-8).
- [ ] **AC-X5.** `bash scripts/lint-squash-ci-directives.sh` is green on the PR body and on the squash message.
- [ ] **AC-X6.** `bash plugins/soleur/test/c4-count-parity.test.sh` is green, which backs "no C4 impact".

## Domain Review

**Domains relevant:** Engineering, Product, Operations, Legal. The other four were assessed and are not
relevant:

- **Marketing:** no public-facing copy, and the capability is operator-facing only (CMO omitted with
  that one-line rationale, per the new-capability mandate).
- **Sales, Finance:** no pipeline or budget-planning surface. The eval spend is recorded under
  Operations.
- **Support:** no support workflow.

### Engineering

**Status:** reviewed (soleur:engineering:cto)

**Assessment:** The substance is sound, but Guard 1 and B5 were over-built. The recommendations and
how each was handled:

| CTO recommendation | Disposition |
|---|---|
| Key acks by (file, skill) | applied |
| Exempt mentions between flipped skills | applied |
| Fold the dispatch groups | applied |
| Trim the mutation matrix | applied; kept M7 because the contract requires a dispatch row |
| Remove the `provision-*` names from `tool-selection-baseline.txt` | applied |
| Reword the `schedule` and `trigger-cron` cron-verb lines | applied |
| Probe the interactive TUI | applied as automated W0-d rather than a manual check |
| Fix B5's statistics: task-clustered SE, stated sampling, INCONCLUSIVE, MWE, a power statement | applied |
| Split B5 into its own PR | persisted as User-Challenge D6.2; default is bundled, per the operator's direction |

Confirmed: ADR-236 and the ADR-151 addendum are the right records, and there is no C4 impact.

### Product

**Status:** reviewed (soleur:product:cpo). **Sign-off given** on the product framing and on the
`aggregate pattern` threshold, with three conditions:

- **C1, interactive TUI before merge.** Applied as W0-d, and it is a merge gate (AC-A6).
- **C2, founder-outcome measurement.** Re-scoped to the W0-f listing probe; the reason is D6.6.
- **C3, the tool-selection baseline.** Applied (D1).

None of the 13 skills first proposed (12 after R1) is founder- or tenant-facing on the web. The CPO's open questions, answered or
tracked:

1. Which model does the web Command Center run on? That decides whether founders there benefit. It is
   recorded in ADR-236 as the scope of the benefit.
2. A separate operator plugin could come later, as the stronger cross-harness fix. It is out of scope
   here and noted in ADR-236's alternatives.
3. Will the no-list entry ever be looked up? The `aliases` field is written in founder words (D6.1).

### Operations

**Status:** reviewed (soleur:operations:coo)

**Assessment:**

- No runbook tells an *agent* to run one of the flipped skills.
- `tenant-provisioning.md`'s `**Skill:**` lines are ambiguous about who runs them. They are reworded as
  operator hand-offs, and runbooks become Guard 1 group 4.
- `flag-bootstrap/SETUP.md` is covered by the Phase 0 sweep.
- The eval's cost goes into `b5-eval-results.md`, and into `expenses.md` if that file has a home for a
  one-off run.
- Out of scope, but noted: the Anthropic API rows in `expenses.md` are past their
  `verify_by=2026-08-30`. That refresh is the ops-advisor's job and is not folded in here.

### Legal

**Status:** reviewed (soleur:legal:clo)

**Assessment:** Nothing blocks. MIT content can be used inside BUSL-1.1, and NOTICE already carries the
full MIT text at the pinned SHA. The rules applied in D4 and Phase 2:

- `official-spec.md` is attributed only if the shingle check or its explanation shows derivation. It is
  otherwise sourced from Anthropic's docs, because a false credit is its own defect.
- The peer paths are written out in full and verified at `c55ee46`.
- The third shingle blob is named (`.agents/invocation.md`).
- The public no-list entry presents Soleur's own measurement, never a claim that the upstream
  technique is wrong.

### Product/UX Gate

**Tier:** none. The plan creates or edits no UI surface: the mechanical UI-surface scan of Files to
Create/Edit matched nothing. The deliverables are frontmatter, markdown references, tests, eval
fixtures and ADRs.

### Plan-time consult (Step 4.5)

A scoped strong-model consult was run on the overview, the phases and the riskiest phase. Adopted:

- W0 moves to Phase 0, before any test, flip or ratchet. It covers the subagent path, the interactive
  path, and Devin/Codex with explicit branches.
- Ack reasons become invocation modes, and `model-mediated` can never be acked.
- B5 moves to free generation in the real ~43 KB corpus, with an INCONCLUSIVE verdict and a
  pre-registered MWE.

Not adopted:

- **Dropping the bare-name scan.** Every flipped name is a hyphenated compound, so the flood the
  advisor predicts does not occur. The bare form is the carry-forward error-1 lesson.
- **Splitting B5.** See D6.2.

## Plan Review Revisions (9-seat panel)

The panel had nine seats, all run headless with no questions asked. Five were the engineering panel:
DHH, Kieran, code-simplicity (fed the Property and Cut Lists, one mechanism at a time),
architecture-strategist and spec-flow-analyzer. Four were named or specialist seats: CPO, CTO (devex
lens), test-design-reviewer, and agent-native-reviewer (the agent-user parity lens).

**Axis rule.** Where the simplification seats (DHH, simplicity) and the correctness seats (Kieran,
architecture, spec-flow, test-design) fired on the same scope, the delete won. Where only correctness
fired, the fix was applied. Mechanical findings were auto-applied. Taste and User-Challenge findings
were persisted to `decision-challenges.md`.

| # | Finding (seat) | Class | Applied change |
|---|---|---|---|
| R1 | `flag-list` is a read-only drift audit the agent must pull itself, so flipping it fails the plan's own test (agent-native P1) | Mechanical | It is kept invocable, which makes the flip set 12 (266 words, 1,733 B). The `flag-delete:20` fix is dropped, and there is no `script-path` escape |
| R2 | A `script-path` ack can route around the typed-yes gates (`delete.sh:146` has no TTY check) (agent-native P1) | Mechanical | The `script-path` reason is deleted. The TTY gap is filed as a follow-up issue |
| R3 | K1-K3 read as "iff", which contradicts M4, so `rclone` would have to flip (architecture P0) | Mechanical | K1-K3 are necessary conditions ("only if"). Membership comes from D1 and is fixed by the pin |
| R4 | Guard 1 missed the shipped plugin hooks, harness lib and Inngest cron prompts (architecture P1) | Mechanical | These are added to G2 and G3, with the reasons for each exclusion stated |
| R5 | The bare-name durable scan, the ack-mode enum and redundant rows are ceremony (DHH, simplicity, CTO devex) | Mechanical (both axes) | The bare-name form moves to the one-time sweeps. The reasons shrink to `doc-mention`/`operator-handoff`. The matrix keeps the rows the contract requires, and each row names the test it reddens (test-design) |
| R6 | Floors per group miss a dead sub-glob, and the scanner could walk a different list (test-design 4) | Mechanical | A floor per glob, plus scanned-count = `ls-files`-count, plus the H3 harness row |
| R7 | Plain pathspecs do not recurse `**` (runbooks: 0 vs 79), and git has no brace expansion (Kieran P1-6) | Mechanical | `:(glob)` pathspecs, one per alternative. Guard 1 moves to its own `invocation-axis.test.ts` |
| R8 | D3 covered only part of the XML prescription, AC-S2 would false-pass, and two line citations were wrong (Kieran P0-1) | Mechanical | A full census table of 9 files. AC-S2 becomes a census grep with an allowlist. Citations corrected (`:32`, not `:3`) |
| R9 | The positive bodies dropped the inline `[id:]`/`[hook-enforced:]` tags (Kieran P0-2) | Mechanical | Tags stay byte-identical in position, and AC-E2 asserts it |
| R10 | The verdict had no positive control and no tested home. `INVALID` sat outside the token set, and precedence was unset (test-design 1-2, spec-flow P0-2) | Mechanical | The committed `rule-phrasing-verdict.cjs`, with fixed precedence, six tokens, and E0 (EXTEND) and E8 (REJECT) controls. An offline `rule-phrasing.test.sh` battery uses the house sentinel verbatim |
| R11 | The inline YAML asserts could not be tested, `max_tokens` cannot be set in the string-list providers, and arm identity depended on file order (Kieran P1-4, P1-5) | Mechanical | `measure-rule-compliance.cjs` keyed on `vars.rule`, `ANTHROPIC_MAX_TOKENS=300`, a truncation rate per arm, and explicit labels |
| R12 | The eval was not re-runnable after EXTEND, and the positive map would rot (spec-flow P1-8, CTO devex 5) | Mechanical | A pinned prohibition body plus a sha256 hash-lock in the fixture |
| R13 | EXTEND might not fit `B_ALWAYS`, and that was discovered only after spending (spec-flow P1-7) | Mechanical | A pre-spend fit check at Phase 3 step 2 |
| R14 | EXTEND had the autonomous run append its own WORM acks, while CODEOWNERS review is not enforced (architecture P1-3) | Mechanical (governance) | EXTEND edits go to a follow-up PR, excluded from auto-merge and reviewed by @deruelle |
| R15 | No scope was defined if W0 stops the flip (spec-flow P0-1). Devin UNVERIFIED let the flip ship unchecked (architecture P1-4) | Mechanical | The W0-STOP profile. Devin is required and measurable with `devin skills list` |
| R16 | A headless run that hits a refusal has no owner, and could re-run the steps by hand (spec-flow P1-3) | Mechanical | The ADR-236 and `authoring-levers.md` policy: stop, file `action-required`, never run the steps by hand |
| R17 | The exempt intra-family group is never read (spec-flow P1-4) | Mechanical | A one-time read, recorded (AC-A7) |
| R18 | The web Command Center dead-ends (spec-flow P1-5), and "list my flags" silently misses in `/soleur:go` (CTO devex 4) | Mechanical | A `go.md` hand-off note outside the gated block, a type-only marker in `help.md`, and an ADR-236 CLI-only statement |
| R19 | The TUI check ran only on the stand-in plugin, and C2 had no pass condition (CPO, spec-flow P1-6) | Mechanical | A real-plugin TUI capture, and an ADR flag when there is "no observed benefit". Post-merge repeat against the released plugin |
| R20 | The no-list entry would fail lint checks 5 and 7, the README forbids an unconfirmed or non-refusal entry, and INCONCLUSIVE reads as a deferral (Kieran P1-3, CPO) | **User-Challenge** (DC-1) | Default: an entry only on REJECT/CEILING, with the scope literal and `->` searched lines, `--all` lint, and typed confirmation as a merge gate. INCONCLUSIVE goes to the ADR and an issue |
| R21 | The corpus belongs in the system message, not the user turn (Kieran P2-12) | Mechanical | Chat-format arms |
| R22 | AC-E6 grepped files the registry test excludes. AC-X4 would fail on the plan's own prose. The ordinal sweep missed the PR body. `lint-rejected-register` runs `--all` in CI. `lint-rule-ids` is a lefthook check, not a CI one (Kieran P2, architecture P2-9) | Mechanical | Each AC and command was corrected |
| R23 | The audit never checks invocation, and a 13th flip has no checklist (spec-flow P2-10/11) | Mechanical | An `audit-skill.md` invocation check, and the checklist in `authoring-levers.md` |
| — | Split B5 into its own PR (CTO, advisor) | User-Challenge (DC-2) | Default: the eval and its verdict stay bundled, and only the EXTEND edits split (R14) |
| — | Drop the `none` arm, or use `--repeat 2` to cut spend (DHH, simplicity optional) | Taste | Not applied. `none` is the only V1 control. The spend cap already falls back to `--repeat 2` |
| — | Cut W0-f, and record Devin/Codex as UNVERIFIED without probing (DHH, simplicity) | Not applied | CPO C2 relies on W0-f, and architecture P1-4 requires the Devin measurement. Both are cheap |
| — | Put the operator-only skills in a separate operator plugin (CPO Q2) | Out of scope | Listed in ADR-236's alternatives |

### Standing panel check — `cq-ac-must-not-depend-on-concurrent-sessions`

Every AC was checked for dependence on ambient or concurrent state. No criterion turns on a sibling
process, and the one-time probes (W0) are recorded as artifacts, not asserted live at merge.

**One sibling-branch hazard remains** (the bundle-3 R16 class). AC-A4's cap equals the *measured*
total, and a concurrent description bump on `main` moves it. The criterion is therefore phrased as
"equals the total the test reports on the merged tree". It is not stated as a literal.

## Test Scenarios

1. The operator types `/soleur:flag-create` in the interactive TUI. It autocompletes and runs (W0-d, real plugin).
2. A model-invocable workflow tells the agent to Skill-invoke `soleur:cron-list`. The agent is refused with `disable-model-invocation`. Guard 1 would have caught that instruction at the M1 shape.
3. An unattended one-shot hits that refusal. The agent stops and files an `action-required` issue naming the command to type. It does **not** run the skill's steps by hand (the ADR-236 policy).
4. An incident session invokes `soleur:trigger-cron`, and an audit invokes `soleur:flag-list`. Both launch (keep-pins).
5. A founder in the web Command Center asks to chase an overdue invoice. `/soleur:go` still reaches `soleur:invoice`.
6. The operator asks the web Command Center to "list my feature flags". It reaches `soleur:flag-list`. Asked to "delete flag X", it replies that the command is CLI-only and names it (`go.md` note).
7. "What's scheduled?" runs `soleur:schedule`'s list step, because its description covers listing.
8. A skill author runs the `soleur:skill-creator` audit on a markdown-headed skill. It raises no XML finding, and it flags a human-only skill that lacks the key.
9. A future PR flips a 13th skill. The pin, the ack table, ADR-236's list and the cap move together in one reviewed diff.
10. The B5 verdicts behave as follows:
    - EXTEND leaves this PR's `AGENTS.rules.md` untouched and opens the follow-up PR;
    - REJECT or CEILING writes the entry, given the confirmation;
    - INCONCLUSIVE writes the ADR row and an issue, with no entry;
    - INVALID or ABORTED allows one rerun;
    - the E0-E9 battery pins all of the above offline.
11. W0-STOP: B5 and B6 ship, there is no flip, ADR-236 is written as `proposed`, and the PR body says `Ref #8290`.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Upstream #92769 (flagged plugin skills hidden from the user) reproduces | W0-d runs in Phase 0 on the probe plugin, and again on the real plugin in Phase 1. A reproduction triggers the W0-STOP profile. Rollback is one key per skill, and the pin makes it an explicit edit |
| #92769 only shows on the *installed* (marketplace) plugin, not on `--plugin-dir` | Post-merge, `soleur:postmerge` repeats the tmux TUI capture against the released plugin. A failure reverts the 12 keys (ADR-236 rollback trigger) |
| Devin hides flagged skills from the user | W0-e is required and measured with `devin skills list`. If the skills are absent or the result cannot be measured, W0-STOP applies |
| Codex ignores the key | That is expected. D2's per-skill 1024-char cap bounds those descriptions, and ADR-236 scopes the budget exclusion to the Claude Code listing |
| A Claude Code upgrade changes the semantics | ADR-236 records the probed version. `soleur:model-launch-review`'s per-release checklist is the re-probe point |
| An agent in an unattended run bypasses the gate by re-running a flipped skill's steps by hand | The ADR-236 and `authoring-levers.md` policy covers it. Mutating scripts' typed-yes prompts lack `[[ -t 0 ]]`, which is filed as a follow-up. `script-path` acks do not exist |
| A sibling PR bumps `SKILL_DESCRIPTION_WORD_BUDGET` | Line 21 conflicts on merge. Recompute from the measured total, never add the two deltas |
| B5 is underpowered (the 2·SE half-width ≈ MWE) | The INCONCLUSIVE verdict writes no public entry (DC-1) |
| B5 spend | Disclosed at 648 calls and ~7.8M input tokens, capped at $60 with a pre-registered `--repeat 2` fallback, and gated by `validate config` |
| An autonomous run approves its own rule weakening | EXTEND edits go to a follow-up PR that is excluded from auto-merge and reviewed by @deruelle |
| ADR ordinal collision (235 is already double-claimed) | Phase 6 re-runs the probe across every `origin/*` ref and sweeps the subject, including the PR body |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. It is filled here (`aggregate pattern`).
- **Never flip a skill that an always-loaded rule names as the agent's own tool.** The repo-research
  pass classified `trigger-cron` SAFE because it searched `soleur:trigger-cron` in the orchestrator
  sense. The rule body at `AGENTS.rules.md:56` names it inside a list of tools the agent itself uses.
  Sweep on the subject, then read each hit.
- **The web Command Center is a model-only entry.** Anything a founder must reach on the web has to
  stay model-invocable, however "human-only" it looks from the CLI.
- **`B_ALWAYS` is not the skill listing.** Quote the budget a saving lands in, with its command.
- **The no-list is for concepts.** If D6.1 is overridden toward ADR-only, delete the entry *before*
  merge. The directory is public and git-permanent.
- **The ack table is not a whitelist to grow casually.** Each row needs a class from the closed enum,
  and `operator-handoff` rows must read as a hand-off to a human in the prose itself.
- **Do not write the literal `eval-gate:block` into any `plugins/soleur/` file**, including README
  prose about the new target: the registry DEDUP scan greps for it (carry-forward error 4).
- **Never flip a read-only probe.** The first planning pass flipped `flag-list` for "human-only by
  nature". Plan-review caught it: an audit the agent must pull itself fails the peer's own test.
  "Operator tooling" is not the same property as "only a human should fire it".
- **Never give a user-invoked skill a `script-path` escape to a mutating script.** The typed-yes
  prompts (`delete.sh:146`) read stdin without a TTY check, so `printf 'yes\n' |` passes them.
- **Guard pathspecs need `:(glob)`.** `git ls-files 'dir/**/*.md'` silently matches 0 files, measured
  at 0 vs 79, and git has no `{a,b}` brace expansion.
- **Under W0-STOP, `closes: 8290` becomes a false claim.** Switch the frontmatter to `refs: 8290`, and
  use `Ref #8290` in the PR body, before the first push.
