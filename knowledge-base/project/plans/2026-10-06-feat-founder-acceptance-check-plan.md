---
title: "feat: founder-defined acceptance check in the brief"
date: 2026-10-06
slug: feat-founder-acceptance-check
branch: feat-acceptance-check-9578
issue: 9578
closes: 9578
type: feat
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: founder-defined acceptance check in the brief

## Overview

Let a founder state, in plain words and before work starts, what proves a piece of work is done. The agent proposes the literal runnable check, the founder approves that exact text, and a step separate from the work runs it and stops to ask on failure. First slice is self-hosted only. It extends the plan's acceptance field and reuses the preflight Check 10 sandbox. No new agent, no new workflow edge, no hosted capture.

**Shape in one paragraph.** `soleur:plan` (interactive) asks "What would you check to know this is done?", stores the answer verbatim as `text` in a `founder_check:` block under `## Acceptance Criteria`, proposes a literal `command` and `expected` string, and gets the founder's approval of that exact text. A baseline run (`soleur:preflight --founder-check-baseline`) proves the check fails before work. The block is committed in a freeze commit that precedes the first code commit. At ship, a new preflight **Check 13** re-verifies the block against the freeze commit, runs the command in the existing Step 10.5 sandbox, and on failure stops and asks the founder (retry, change the check, accept anyway). "Accept anyway" is recorded as `OVERRIDDEN`, never as passed.

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #9578, #9577, #9620, #9588 are all OPEN; ADR-175 and ADR-229 exist on `origin/main`; no `founder_check` token exists anywhere in the tree outside this feature's own spec and brainstorm (`git grep` over `*.md *.ts *.sh *.py`). Held: every cited reference. Stale: one claim in the brainstorm — "no ADR-229 change unless a back-edge is added" — is imprecise, because the back-edges this feature would use (`ship → work`, `review → work`) are already declared (see Q(e)). The repo-research subagent also asserted "no spec or brainstorm exists for #9578"; both exist, so its uncorroborated statements were re-verified against code before use.

### Property List and Cut List (Phase 0.6b)

Properties the feature must buy:

1. The founder states what proves "done", in their own words, before work starts.
2. The founder approves the exact runnable text, not a paraphrase.
3. After approval the text cannot change unnoticed.
4. The check fails before the work and is therefore not vacuous.
5. A step other than `work` runs it, and the result states only what is true.
6. A failure stops and asks; an override is recorded as an override.

| Mechanism proposed by the ask or the brainstorm | Property it buys | Verdict |
|---|---|---|
| New agent for acceptance checks | none beyond existing preflight | **Cut** — issue: "do not build a new engine"; preflight already owns sandbox + headless FAIL + aggregate |
| New ADR-229 workflow edge | 6 | **Cut** — `ship → work` and `review → work` already exist (Q(e)) |
| Hosted Command Center capture | 1 | **Cut** from slice 1 — waitlist-only, #9620 |
| Run from `qa` | 5 | **Cut** — `qa/SKILL.md` is 36,992 of a 37,000-byte ceiling (8 bytes headroom); qa runs Browser/API scenarios, a different authority |
| New standalone skill | 5 | **Cut** — adds `description:` words against a 2413/2413 budget and a new ceiling row |
| Generalising Check 10 in place | 5 | **Cut** — Check 10 is gated on a sensitive-path diff, resolves the plan from the PR body, SKIPs on `credentials_required` and 401/403, and matches by OR-tokens; every one of those semantics is wrong for a founder check |
| New preflight Check 13 reusing Step 10.5 | 4, 5 | **Kept** |

### Repo facts that shaped the design (verified, content anchors)

- Preflight already has Check 11 (Domain-Model Register Drift) and Check 12 (Encryption Posture). The new check is **Check 13**.
- The sandbox is the inline `BWRAP_ARGS=(` array in preflight `### Step 10.5`; `preflight-discoverability-test.test.ts` and `scripts/lint-window-closure-assertion.py` pin it there. It is **not** extracted in this plan: Check 13 *runs Step 10.5 with `CMD` set to the founder command* and carries no sandbox of its own (Guard 4).
- ADR-229 is a skill-level lifecycle FSM (`DECLARED_TRANSITIONS` in `plugins/soleur/lib/workflow-fidelity.ts`). `preflight` and `qa` are non-node skills, dropped by the offline classifier before pairing. It models no "stopped awaiting operator" state.
- Lifecycle body ceilings (`plugins/soleur/test/skill-body-budget.json`, ratchet down only): brainstorm 140,875/141,000 B, plan 119,864/120,000 B, qa 36,992/37,000 B, work 361,760/362,000 B, ship 273,995/274,000 B. `preflight` has no ceiling row (113,570 B).
- `SKILL_DESCRIPTION_WORD_BUDGET` is 2413 with 2413 used (headroom 0, measured through the same `discoverSkills()` path by `bun test … -t "cumulative description word count"`, passing). It counts only `description:` frontmatter, so body prompt text does not spend it, and this plan edits no description.
- Next free ADR ordinal on `origin/main` is **ADR-274** (ADR-273 is the highest). Provisional; `soleur:ship` re-verifies.
- Layer-7 observability rule: a self-hosted CLI surface has **no Soleur-side sink, by design**; it needs a stdout marker plus a durable committed artifact and a discoverability test that reads that artifact (`observability-coverage-reviewer.md` layer 7).

### Institutional learnings applied

- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — a guard's window narrower than its property; drives the Guard Contract below.
- `2026-09-18-every-mechanism-was-validated-against-the-tree-before-its-own-backfill.md` — validate against the tree the remediation produces: the founder-approved text itself must not be re-written by the plan skill on re-run.
- `2026-07-20-a-correction-pr-verified-the-old-claim-was-gone-not-that-the-new-one-was-supported.md` — claim wording; a pass claims only "ran and returned success".
- `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` — measure headroom at plan time (done above).
- `2026-07-05-adr-renumber-must-sweep-planning-docs-and-scripts-glob-orphan.md` — the ADR ordinal is provisional; sweep this plan, tasks and any AC that names it on renumber.

### Open Code-Review Overlap

One open `code-review` issue touches planned files: **#4133** (schema parity test for the `## Observability` block) names `plugins/soleur/skills/plan/SKILL.md` and `plan-issue-templates.md`. **Acknowledge** — this plan adds a `founder_check:` sub-field, not an Observability schema change; #4133 stays open. No other overlap across the 10 planned path groups.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Reality | Plan response |
|---|---|---|
| TR2: "a new check or a generalised Check 10" | Check 10 gates and match semantics are wrong for this use (Cut List) | New **Check 13**; reuses Step 10.5 and `probe-verb-gate.sh` only |
| TR3: tests extend `preflight-discoverability-test.test.ts`, `plan-skeleton-checkpoint.test.ts`, `preflight-check10-suite-integrity.test.sh`, fixtures under `fixtures/preflight-check-10/` | Those suites and fixtures are about Check 10 and its parser. A new behaviour needs its own suite | New `preflight-founder-check.test.ts` + `fixtures/founder-check/`; the three named files get *small* extensions (anti-fork chokepoint pin, floor, skeleton-compat) — see Phase 1 |
| FR1: prompt in "brainstorm and plan" | Brainstorm body has 125 bytes of ceiling headroom; ceilings only ratchet down in a separate reviewed PR | **Plan-only in v1**; brainstorm half deferred to a tracked issue (see Scope Check, row 14) |
| FR5: a separate step runs it "from the committed text" | Preflight's Check 10 resolves the plan from a regex over the PR body, which the agent can edit | Check 13 resolves the plan from the branch (`branch:` frontmatter match), never the PR body |
| Brainstorm: "CTO read only part of ADR-229" | Full read (504 lines): no change needed | See Q(e) |

## Answers to the plan-stage questions

**Q(a) — qa or a new preflight-style check?** A new **preflight Check 13**. qa has 8 bytes of body headroom and runs Playwright/API scenarios under a different authority. Preflight is uncapped, already owns the sandbox, the verb gate, the headless "FAIL aborts, no prompt" contract and the Phase 2 aggregate, and runs at ship Phase 5.4 on both the interactive and the one-shot path. A baseline mode (`--founder-check-baseline`) reuses the same Check 13 in must-fail polarity before work.

**Q(b) — how the frozen text survives plan amendment.** Three rules.

1. *Anchor in history, not in the file.* The first commit in `origin/main..HEAD` whose plan carries the block is the **freeze commit**; it must precede the first commit that touches anything outside `knowledge-base/project/{brainstorms,plans,specs}/`. A block first committed together with, or after, code is `FAIL: not approved before work`.
2. *Compare canonical fields, not bytes.* HEAD's `text`, `command`, `expected`, `creates` are compared to the freeze commit's. Reformatting passes; any edit is `CHANGED-SINCE-APPROVAL`. Freeze exists but no block at HEAD is `FAIL`, never `SKIP`.
3. *The founder is the authority on any change.* A difference is shown (old and new text) and, interactively, needs an explicit founder confirmation; headless it is `FAIL`. A confirmed change runs with outcome label `PASSED-WITHOUT-BASELINE` because the pre-work tree no longer exists to baseline against. Re-running `soleur:plan` on a branch that already carries a freeze commit **imports the block verbatim and does not re-ask**.

This is tamper-*evident*, not tamper-proof: an agent that rewrites branch history or forges `approved_by` is not stopped by a hash it also controls. The ADR names that residual (same class as ADR-175's PR-head circularity) and the log makes every difference visible in the PR diff.

**Q(c) — fail / retry / override flow** (spec-flow analysis run; the 8 decisions it forced are folded in).

| State | Detection | Check 13 result | Interactive | Headless / one-shot |
|---|---|---|---|---|
| No block, no freeze evidence | plan has none | **SKIP** — banner "No founder-stated check was defined. Nothing was run on your behalf." | continue | continue (same banner) |
| Freeze evidence, no block at HEAD | history vs plan | **FAIL** | stop | abort |
| Block with no earlier freeze commit | ancestry | **FAIL** — not approved before work | stop | abort |
| More than one `founder_check` block | parse | **FAIL** | stop | abort |
| Block differs from freeze | canonical compare | **CHANGED-SINCE-APPROVAL** | founder confirms or rejects | **FAIL** |
| `kind: judgement` | block | **NEEDS-YOUR-EYES** — evidence shown, founder answers yes/no | founder decides | **FAIL** (STOPPED) — an agent never decides |
| bwrap absent / cannot establish | Step 10.5 probe | **SKIP-NOSANDBOX** — "your check did not run on this host" | continue, stated | continue, stated |
| Command ran, returned success and `expected` present | classify | **PASSED** (wording below) | continue | continue |
| Command ran, non-zero or `expected` absent | classify | **FAILED** | retry (max 3 per hash) / change the check / accept anyway | **FAIL** — outcome `STOPPED-AWAITING-FOUNDER`; never auto-overridden |
| rc in {6, 7, 28, 124, 126, 127} or sandbox error | classify | **INVALID** (tooling, not a result) | change the check / accept anyway (no retry-into-pass) | **FAIL** |
| Founder picks "accept anyway" | interactive answer + one-line reason | **OVERRIDDEN** — its own terminal, flagged in the table | recorded, continue | impossible |

Every attempt is logged with `attempt_n`; a pass after failures prints "PASSED on attempt N after M failures". `OVERRIDDEN` and `CONFIRMED-CHANGE` are written only after an interactive answer in the same session (Guard 3 states the limit of that control).

**Q(d) — does the skill-description budget allow the prompt text?** The description budget (2413/2413, headroom 0) is not the constraint: it counts `description:` frontmatter and this plan edits none. The real constraint is the **body ceilings** above. So the prompt text lives in a new `plan/references/plan-founder-check.md` (not a SKILL.md body) with a single pointer line in `plan/SKILL.md` of at most 130 bytes (136 available); `work/SKILL.md` may take one rule line of at most 230 bytes (240 available) or none, because the gate enforces the rule anyway; `brainstorm` is not touched.

**Q(e) — does ADR-229 need to change?** **No**, confirmed by a full read of both ADRs. ADR-229 models skill-level transitions only; `preflight` is a non-node skill the classifier drops (`nonnode=`); "check failed, back to work" is the existing `ship → work` / `review → work` edge (its doc comment already names "preflight/QA failed"); "stopped awaiting operator" and "override" are not FSM concepts. Nothing is added to `ONE_SHOT_CHILD_SKILLS`, `IMPLEMENTATION_TAIL` or `DECLARED_TRANSITIONS`, so `workflow-fidelity.test.ts` and `skill-body-budget.json` are untouched. The new ADR records this verification so the next reader need not redo it. **ADR-175 does need an amendment** (see Architecture Decision).

## Design

### The `founder_check` block

A fenced YAML block under `## Acceptance Criteria` in the plan (all three templates carry the same sub-field):

```yaml
founder_check:
  kind: command              # command | judgement
  text: ""                   # the founder's own words, verbatim
  command: ""                # the literal command the founder approved (kind: command)
  expected: ""               # one literal substring of stdout; empty means "exit 0 only"
  creates: []                # optional repo-relative paths the work will create (baseline target-absent rule)
  approved_by: ""            # recorded from the interactive answer
  approved_at: ""            # UTC date
  hash: ""                   # sha256 over canonical {kind,text,command,expected,creates}
```

Rules enforced by `founder-check.py` (not prose): first token on `PROBE_VERB_ALLOWLIST` via `probe-verb-gate.sh`; the Step 10.5 shell-active-token reject; no `credentials_required` (a check needing credentials becomes `kind: judgement`); `expected` is **one exact literal substring** (no Check 10 OR-tokenisation); a single block per plan in v1.

### Result wording (single source: constants in `founder-check.py`, pinned by tests, CLO-reviewed)

- Pass: "Your check passed. This shows only that the check you wrote ran and returned success. It does not confirm the work is correct, complete or safe. Review the result before relying on it."
- First-use notice: "A vague, wrong or unsafe check can pass broken work or run actions you did not intend. Read what will run before it runs."
- Never the words "verified", "proven" or "safe". Passes and failures are shown with equal prominence: exact command, UTC time, rc, bounded output.

### What is committed (leakage rule)

`knowledge-base/project/specs/<branch>/founder-check-log.md` is append-only and records, per attempt: kind, command, rc, outcome, `attempt_n`, `tested_sha`, block hash, UTC time, `output_sha256`, and the first 200 bytes of stdout **only if** it matches none of the secret-shape patterns (token prefixes, PEM headers, bearer strings); otherwise the hash alone and "output withheld". Full output is shown in the terminal only. At capture the founder is told that `text` and `command` are committed to the repository.

## Implementation Phases

Test-first (`cq-write-failing-tests-before`): Phases 1 and 2 are RED then GREEN. Phases 1–3 are the gate; Phases 4–5 are capture and decision record. The gate is inert without capture, and capture is a lie without the gate, so they ship together; the boundary is the split seam if the work grows (Scope Check, Split Assessment).

### Phase 0 — Preconditions

- 0.1 Re-verify the next free ADR ordinal against `origin/main` (`git ls-tree --name-only origin/main knowledge-base/engineering/architecture/decisions/`).
- 0.2 Re-measure body ceilings and the description budget; record numbers in the PR body.

### Phase 1 — Failing tests and fixtures (RED)

- 1.1 `plugins/soleur/test/preflight-founder-check.test.ts` drives the production `founder-check.py` (not a TypeScript mirror) over `fixtures/founder-check/*.md` plus synthesized git histories built with `gitFixture()` (see plugin AGENTS.md "Test Fixture Conventions"; never a hand-rolled git env).
- 1.2 Fixtures (synthesized only, `cq-test-fixtures-synthesized-only`): valid block; reformatted-but-equal block; edited command; edited expected; deleted block after freeze; two blocks; block committed with code; `hash:` removed; `creates:` stub already present; `credentials_required` present; trivial verb; judgement kind; rebase-changed SHAs; and token-shaped output fixtures for the leakage scrub.
- 1.3 Extend `preflight-check10-suite-integrity.test.sh` with an anti-fork floor: exactly one `BWRAP_ARGS=(` in `preflight/SKILL.md` and none inside the Check 13 section (Guard 4). Extend `preflight-discoverability-test.test.ts` only to assert Check 10 behaviour is unchanged. Extend `plan-skeleton-checkpoint.test.ts` to assert a plan carrying a `founder_check` block under `## Acceptance Criteria` still satisfies the completion predicate.
- 1.4 Run the suites; every new case must be RED for the right reason (script absent), recorded in the PR body.

### Phase 2 — `founder-check.py` (GREEN)

Stdlib-only Python at `plugins/soleur/skills/preflight/scripts/founder-check.py`, subcommands `parse`, `hash`, `verify-freeze`, `classify`, `log`, `summary`, and the wording constants. It **never executes the founder command** (Guard 4); `classify` is a pure function of `(rc, stdout, expected, polarity, creates, target_present)` shared by baseline and acceptance polarity, so there is one decision chokepoint.

### Phase 3 — preflight Check 13

Edit `plugins/soleur/skills/preflight/SKILL.md` (uncapped): add `### Check 13: Founder-Stated Check` after Check 12; the Phase 2 aggregate row (`PASS / FAIL / SKIP / SKIP-NOSANDBOX / OVERRIDDEN`); the fast-path overview row ("never SKIPs on an empty cache; runs whenever a plan for this branch carries a `founder_check` block or freeze evidence"); the headless paragraph (Check 13 `SKIP-NOSANDBOX` and the no-block banner are always emitted, like Check 10's); the `--founder-check-baseline` mode; and a Sharp Edges entry. Check 13 runs Step 10.5 unchanged with `CMD` set to the founder command and emits the metadata-only marker `SOLEUR_FOUNDER_CHECK_RESULT outcome=… hash=… tested_sha=…` (no command text, no output).

### Phase 4 — Capture (plan side)

- 4.1 Create `plugins/soleur/skills/plan/references/plan-founder-check.md`: the question, the proposal/approval loop, vague-check rewrite or `needs-your-eyes`, the first-use notice, the capture-time leakage warning, the baseline invocation, the `creates:` rule, headless behaviour (no question asked; no block written), and the import-on-rerun rule.
- 4.2 One pointer line in `plan/SKILL.md` (≤130 bytes). Verify with `python3 scripts/lint-skill-body-budget.py` against the merge base. If the line does not fit, trim an equal number of bytes elsewhere in the same file in the same edit; never raise a ceiling.
- 4.3 Add the `founder_check:` sub-field under `## Acceptance Criteria` in the MINIMAL, MORE and A LOT templates of `plan-issue-templates.md`.
- 4.4 `work/SKILL.md`: one rule line, at most 230 bytes, "never edit the plan's `founder_check:` block; change it only through `soleur:plan`", or omit if it does not fit.

### Phase 5 — Decision record and architecture

- 5.1 ADR-274 (provisional) and the inline ADR-175 amendment (Architecture Decision, below).
- 5.2 `model.c4`: edit the `contributor` description and the adjacent comment (Architecture Decision, C4 views); run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 6 — Verification

- 6.1 `bun test plugins/soleur/test/preflight-founder-check.test.ts plugins/soleur/test/preflight-discoverability-test.test.ts plugins/soleur/test/plan-skeleton-checkpoint.test.ts plugins/soleur/test/components.test.ts` and `bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh`.
- 6.2 `python3 scripts/lint-skill-body-budget.py`, `python3 scripts/lint-guard-contract.py` on this plan, and the repo markdown lint.
- 6.3 Trace `soleur:ship` to confirm `specs/<branch>/founder-check-log.md` is staged by its existing artifact commit (Phase 6). If it is not, the fix is a one-line instruction printed by Check 13 ("commit this file"), not a commit made inside preflight.
- 6.4 CLO review of the final prompt, notice and result wording (spec acceptance criterion) before the PR leaves draft.

## Files to Create

- `plugins/soleur/skills/preflight/scripts/founder-check.py`
- `plugins/soleur/skills/plan/references/plan-founder-check.md`
- `plugins/soleur/test/preflight-founder-check.test.ts`
- `plugins/soleur/test/fixtures/founder-check/` (fixture set, ~14 files; counted as one entry)
- `knowledge-base/engineering/architecture/decisions/ADR-274-founder-stated-acceptance-check-frozen-separately-executed.md`

## Files to Edit

- `plugins/soleur/skills/preflight/SKILL.md`
- `plugins/soleur/skills/plan/SKILL.md` (one pointer line, ≤130 bytes)
- `plugins/soleur/skills/plan/references/plan-issue-templates.md`
- `plugins/soleur/skills/work/SKILL.md` (one rule line, ≤230 bytes, or omitted)
- `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`
- `plugins/soleur/test/preflight-discoverability-test.test.ts`
- `plugins/soleur/test/plan-skeleton-checkpoint.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-175-preflight-probe-execution-boundary.md` (inline amendment)
- `knowledge-base/engineering/architecture/diagrams/model.c4`

**Not edited, on purpose:** `qa/SKILL.md`, `ship/SKILL.md`, `brainstorm/SKILL.md` (ceiling headroom of 8, 5 and 125 bytes), `plugins/soleur/lib/workflow-fidelity.ts`, `.claude/workflow-transitions.json`, `skill-body-budget.json`, any `description:` frontmatter.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Let the founder state "what proves this is done" in the brief" [issue #9578] | Phase 4, `plan-founder-check.md`, template field | mapped |
| 2 | "have an agent run that check before work counts as done" [issue #9578] | Phase 3, Check 13 | mapped |
| 3 | "extend the plan-phase acceptance field; do not build a new engine" [issue #9578] | `founder_check:` under `## Acceptance Criteria`; Cut List | mapped |
| 4 | "the founder approves the exact runnable check" [brief] | Phase 4.1 approval loop; `approved_by` | mapped |
| 5 | "it is frozen with a hash and must fail before work starts" [brief] | freeze commit + `hash`; Phase 3 baseline mode; Guards 1–2 | mapped |
| 6 | "a separate step runs it" [brief] | Check 13 in preflight, never `work` | mapped |
| 7 | "a failure stops and asks" [brief] | Q(c) table; Check 13 | mapped |
| 8 | "Self-hosted only first." [brief] | hosted capture Cut; no web-platform edits | mapped |
| 9 | "Extend the plan acceptance field and the preflight Check 10 sandbox path." [brief] | template edit; Check 13 runs Step 10.5 | mapped |
| 10 | "No new agent, no new workflow edge." [brief] | Cut List; Q(e) | mapped |
| 11 | "An ADR amending ADR-175 is required." [brief] | Phase 5.1 | mapped |
| 12 | "whether it runs from qa or a new preflight-style check; how the frozen text survives a plan amendment during work; the fail/retry/override flow (run spec-flow)" [brief] | Q(a), Q(b), Q(c) | mapped |
| 13 | "whether the skill-description budget allows the prompt text; whether ADR-229 really needs no change" [brief] | Q(d), Q(e) | mapped |
| 14 | "The self-hosted brainstorm and plan prompts ask" [spec FR1] | plan prompt only | descoped — justification: `brainstorm/SKILL.md` has 125 bytes of ceiling headroom and ceilings only ratchet down in a separate reviewed PR; the plan prompt always runs after a brainstorm, so the founder experience is the same; tracked in a deferral issue |
| 15 | "The CLO has reviewed the final UI and result wording." [spec acceptance] | Phase 6.4 | mapped |
| 16 | "No marketing, changelog or demo copy claims the feature before it ships." [spec acceptance] | no docs, blog, landing or changelog-copy edits in this plan | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plan-founder-check.md`, template field, plan pointer | "Let the founder state "what proves this is done" in the brief" | asked |
| `preflight/SKILL.md` Check 13 | "a separate step runs it" | asked |
| freeze commit + `hash` | "it is frozen with a hash" | asked |
| baseline mode | "must fail before work starts" | asked |
| ADR-274 + ADR-175 amendment | "An ADR amending ADR-175 is required." | asked |
| `work/SKILL.md` rule line | "`work` must not edit the frozen block" [spec TR1] | asked |
| `founder-check.py` | — | inferred — justification: parse, canonical hash, history ancestry and classification are deterministic decisions that need a testable implementation; spec TR3 requires "mutation proof that a founder-approved check cannot be edited, weakened or satisfied vacuously", which prose in a SKILL.md cannot supply |
| `creates:` field | — | inferred — justification: without it the commonest check ("the new script prints ok") can never be baselined, because the target is absent for the wrong reason; spec FR3's must-fail rule would otherwise reject it |
| INVALID classification | — | inferred — justification: a tooling failure (timeout, command not found) would otherwise count as a valid baseline fail, certifying a check that can never pass |
| retry cap of 3 and per-attempt log | — | inferred — justification: unbounded retry lets an agent fish for a pass; spec FR5 says failures stop and ask |
| `founder-check-log.md` | "Show the exact command, the time and the output, and show passes and fails equally" [brainstorm] | asked |
| `kind: judgement` | "Judgement checks go to the founder as a yes/no with evidence" [brainstorm] | asked |
| `model.c4` contributor edit | — | inferred — justification: the C4 completeness mandate; the `contributor` description states the discoverability probe is the *one* PR-head artifact preflight executes, which Check 13 makes false |
| three test-file extensions (check-10 suite-integrity, discoverability, skeleton) | "Tests extend `plugins/soleur/test/preflight-discoverability-test.test.ts`, its fixtures under `fixtures/preflight-check-10/`, `plan-skeleton-checkpoint.test.ts` and `preflight-check10-suite-integrity.test.sh`" [spec TR3] | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 14 entries (fixture set counted once) | Estimated changed lines: ~1,300 (about 550 are tests and fixtures, 120 ADR prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the line count crosses the threshold on mechanical test/fixture volume, not on scope; a split (gate in PR 1, capture + ADR in PR 2) was considered and rejected because the gate is inert without capture and a founder-facing prompt without the gate would claim a check that nothing runs. The Phase 3/Phase 4 boundary is the seam if work grows past this estimate.

## Acceptance Criteria

- [ ] `soleur:preflight` Check 13 exists after Check 12, with the Phase 2 aggregate row and the fast-path overview row, and runs the founder command only through Step 10.5; `BWRAP_ARGS=(` still occurs exactly once in `preflight/SKILL.md`.
- [ ] A plan with a freeze commit and no block at HEAD returns FAIL, never SKIP (fixture + test).
- [ ] An edit to `command`, `expected` or `creates` after the freeze is rejected; a pure YAML reformat of the same fields passes (mutation proof, Guard 1 rows 1, 4).
- [ ] A block first committed together with or after code is FAIL; a rebased branch with new SHAs but an earlier freeze commit still passes.
- [ ] Re-running `soleur:plan` on a branch carrying a freeze commit imports the block and does not re-ask or drop it.
- [ ] A baseline that passes is rejected as `VACUOUS`; rc 124/126/127/6/7/28 and a sandbox error classify as `INVALID`, never as a baseline fail or an acceptance pass; a `creates:` target absent at baseline is valid only when listed in `creates:`.
- [ ] `OVERRIDDEN` and `CONFIRMED-CHANGE` are produced only on an interactive-answer code path; a headless run with a failing check yields `STOPPED-AWAITING-FOUNDER` and a FAIL (test greps both paths).
- [ ] The result wording, first-use notice and the words "verified", "proven", "safe" are pinned: the constants match the spec text exactly and no output string contains the three banned words (test).
- [ ] `founder-check-log.md` is append-only (a rewritten earlier line is rejected), stores only a bounded scrubbed prefix, and token-shaped output fixtures are stored as a hash with "output withheld".
- [ ] No-bwrap hosts report `SKIP-NOSANDBOX` with "your check did not run on this host", and baseline capture is refused (judgement only).
- [ ] `python3 scripts/lint-skill-body-budget.py` is green against the merge base; `plan/SKILL.md` grew by at most 136 bytes and `work/SKILL.md` by at most 240 bytes; no `description:` changed; `components.test.ts` budget test still passes at 2413/2413.
- [ ] ADR-274 exists (ordinal re-verified against `origin/main`), the ADR-175 inline amendment is present, ADR-229 and `workflow-fidelity.ts` are unmodified, and `model.c4` edits pass `c4-code-syntax`, `c4-render` and `c4-count-parity`.
- [ ] `python3 scripts/lint-guard-contract.py` reports 4 entries for this plan.
- [ ] The CLO has reviewed the final prompt, notice and result wording; no marketing, changelog or demo copy claims the feature.

## Test Scenarios

- Given a founder who answers the plan prompt with a check that already passes, when the baseline runs, then the plan reports VACUOUS and offers: strengthen the check, mark it needs-your-eyes, or record it as already true and drop it (a dropped check never reappears as a pass).
- Given an approved check and a finished feature, when ship runs preflight, then Check 13 reports PASSED with the exact pass wording, the command, the time and the output, and appends one log row.
- Given the check fails at ship in an interactive session, when the founder picks "accept anyway" and types a reason, then the table shows OVERRIDDEN, the log row says so, and nothing says "passed".
- Given a one-shot run whose plan carries a block and the check fails, when preflight runs headless, then the pipeline aborts with STOPPED-AWAITING-FOUNDER and no override is possible.
- Given `work` reformats the plan and edits `expected`, when Check 13 runs, then CHANGED-SINCE-APPROVAL shows both texts; interactive asks, headless fails.
- Given a macOS host, when capture starts, then the founder is told the check cannot run here and may only record a needs-your-eyes check.
- Verification of the PR itself (consumed by `soleur:qa`): **API verify:** `python3 plugins/soleur/skills/preflight/scripts/founder-check.py summary` expects the line `founder-check:`.

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Marketing (carried forward from the brainstorm's `## Domain Assessments`; no fresh sweep)

### Engineering

**Status:** reviewed (brainstorm carry-forward, extended by the full ADR-175/229 read)
**Assessment:** Small-to-medium; freeze and hash the text, run it in a different step from the work, reject a check that already passes, reuse the Check 10 sandbox without calling it a security boundary; needs an ADR. The plan confirms ADR-229 needs no change and that ADR-175 needs an amendment.

### Product

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Build now, narrowly; the founder never defines engineering "done" today. Self-hosted prompt first; judgement checks go to the founder; a failure stops and asks.

### Legal

**Status:** reviewed (brainstorm carry-forward) — conditions carried as acceptance criteria
**Assessment:** A "passed" label may claim only that the founder's check ran and returned success; show the derived command; first-use notice; no marketing claim before ship; hosted copy waits for #9620; a hosted data-reading path would trigger the GDPR gate. CLO review of final wording is Phase 6.4.

### Marketing

**Status:** reviewed (brainstorm carry-forward)
**Assessment:** Position as "your standard, checked", never "verified"; no claim before it exists. This plan ships no copy.

### Product/UX Gate

**Tier:** none
**Decision:** auto-accepted (pipeline) — the mechanical UI-surface override found no UI-surface path in Files to Create/Edit (SKILL.md, scripts, tests, ADR, `.c4`); the first slice is prompt text in a CLI, not a page, component, modal or flow (`ui-surface-terms.md` §Excluded)
**Agents invoked:** soleur:product:spec-flow-analyzer (flow analysis of fail/retry/override, requested by the spec)
**Skipped specialists:** none — no domain leader recommended soleur:product:design:ux-design-lead, soleur:marketing:copywriter or soleur:marketing:conversion-optimizer
**Pencil available:** N/A (no UI surface)

#### Findings

The spec-flow pass produced eight decisions, all folded into Q(b)/Q(c), the Guard Contract and the acceptance criteria. Declined with reason: a trivial-`expected` denylist (the baseline must-fail run is the discriminator, so a short literal is safe); a multi-check list (single block in v1, deferred); PR-body labels and a `founder-override` PR label (need `ship/SKILL.md`, which has 5 bytes of headroom; the committed log and the preflight table carry the signal in v1, deferred).

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder-stated check marked passed when it never ran or never discriminated, so they merge work believing their own standard was met.
- **If this leaks, the user's workflow is exposed via:** the committed `founder-check-log.md` and the plan's `founder_check` block, which carry the founder's own words, a runnable command and a prefix of its output into a repository that may be public; and the executed command itself, which runs with network egress inside the Step 10.5 sandbox.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one founder who trusts a "passed" label on broken work, or whose command output leaks a token into a public repo, is a single-user brand incident; an aggregate-pattern tier would under-weight that.

`requires_cpo_signoff: true` — the CPO assessment from the brainstorm carries forward; `soleur:engineering:review:user-impact-reviewer` is invoked at review time. Brainstorm-stage CLO and CTO concerns are reflected in the wording constants, the leakage rule, and the Guard Contract.

## Observability

Self-hosted CLI surface: layer 7 (`cli-stdout-artifact`). By design there is **no Soleur-side sink**; routing a founder's run to Soleur infrastructure would ship repository-derived data to a vendor.

```yaml
liveness_signal:
  what: SOLEUR_FOUNDER_CHECK_RESULT stdout marker per Check 13 run (outcome, hash, tested_sha only) plus a committed append-only founder-check-log.md row
  cadence: per preflight run
  alert_target: the founder in-session via the preflight result table; no remote alert, by design (layer 7)
  configured_in: plugins/soleur/skills/preflight/SKILL.md Check 13 and plugins/soleur/skills/preflight/scripts/founder-check.py

error_reporting:
  destination: tool-result stdout in the founder's own session plus the committed log artifact in their own repository
  fail_loud: Check 13 returns FAIL, aborts headless preflight, and prints the outcome label; an unparseable block is FAIL, never SKIP

failure_modes:
  - mode: freeze evidence exists but the block is missing or altered
    detection: founder-check.py verify-freeze compares canonical fields to the freeze commit and returns FAIL or CHANGED-SINCE-APPROVAL
    alert_route: Check 13 table row in the founder's session (layer 7)
  - mode: sandbox cannot be established so the check never ran
    detection: SKIP-NOSANDBOX line plus SOLEUR_FOUNDER_CHECK_RESULT outcome=SKIP-NOSANDBOX, stated as "your check did not run"
    alert_route: stdout in-session (layer 7), and the log row
  - mode: command output matches a secret shape
    detection: the scrub stores output_sha256 only and writes "output withheld" into the log
    alert_route: the log row in the founder's repository (layer 7)

logs:
  where: knowledge-base/project/specs/<branch>/founder-check-log.md, committed to the founder's own repository
  retention: lives with the repository history

discoverability_test:
  command: python3 plugins/soleur/skills/preflight/scripts/founder-check.py summary
  expected_output: founder-check:
```

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-274** (provisional ordinal) "Founder-stated acceptance check: frozen, separately executed", terse shape with an `## Alternatives considered` table (qa home, new skill, generalised Check 10, new agent, new ADR-229 edge) and `related_adrs: [ADR-175, ADR-229]`. It records: the freeze-commit anchor and why the hash alone is self-certification; the INVALID/VACUOUS/PASSED/FAILED/OVERRIDDEN vocabulary; the ADR-229 full-read verification; the ship stale-pass window (a pass at preflight can precede code-mutating Phase 5.5 gates; `tested_sha` is recorded so the reader can see it); and the named residuals (agent-controlled history, forged `approved_by`, shared network namespace).
- **Amend ADR-175** with an inline blockquote under its Layer 1 heading, in that file's existing `> **YYYY-MM-DD amendment (#N).**` convention: Layers 1 and 2 apply unchanged to a founder-approved command; founder approval is a legibility and consent step, not an authority grant; credentialed checks are not given a waiver path (they become judgement checks); the three counterweights against self-certification are carried by Guards 1–3.
- **ADR-229: no change** (Q(e)); the ADR-274 text says so with the evidence.

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` were read in full for this section, not grepped for the feature noun.

- (a) *External human actor*: the `founder` actor already exists and is modelled as the workspace Owner running Soleur skills in the CLI. The `contributor` actor (untrusted PR author) is relevant because a contributor's PR can carry a plan with a forged `founder_check` block.
- (b) *External system / vendor*: none added; the check runs locally in the existing bwrap sandbox, no new integration edge.
- (c) *Container / data store*: none; the log is a file in the founder's repository.
- (d) *Actor↔surface access relationship*: unchanged for `founder`; for `contributor`, the one-artifact statement changes.
- **Edit `model.c4`:** the `contributor` element's description says "The one PR-head artifact preflight executes on the operator's own workstation — a plan-declared discoverability probe", and the comment above it says "preflight Check 10 executes a plan-declared probe". Both become false with Check 13, which executes a second PR-head artifact (a plan-declared `founder_check` command) in the same sandbox. Update both to name the two artifacts and keep the comment and description in agreement (they disagreed once, #7393 review). No `views.c4` change: no element is added and `contributor` already renders.
- Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (no cardinality moves; the run proves it).

### Sequencing

The ADR describes the target state and is authored in this PR, not postponed. Status `accepted` at merge; no soak.

## Guard Contract

### Guard 1 — Frozen-block integrity

**Property.** A `founder_check` block that passes Check 13 equals, on its canonical fields, the block in a freeze commit that precedes the branch's first code commit, or the founder confirmed each difference at the gate.

**Assembly.** Every path by which block text reaches the gate: the plan file on the branch (resolved by `branch:` frontmatter, never the PR body), the freeze commit's copy (found by content in `origin/main..HEAD`), and every writer of the plan — `soleur:plan` re-run, `deepen-plan`, `plan-review`, `work`, review fix commits. The one chokepoint is `founder-check.py verify-freeze`, the sole parser and hasher, shared by baseline and acceptance polarity; the SKILL.md prose contains no second comparison.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Edit `command` in the HEAD block after the freeze commit | RED (CHANGED-SINCE-APPROVAL; headless FAIL) |
| 2 | Run `verify-freeze` over a branch that has a freeze commit and a plan with zero blocks (the guard's own dispatch reporting "0 checked") | RED (FAIL, never SKIP) |
| 3 | Add a second, differing `founder_check` block after a compliant first | RED (more than one block) |
| 4 | Delete `hash:` while keeping the block | RED |
| 5 | Commit the block in the same commit as the first code change | RED (not approved before work) |
| 6 | Edit `expected` and recompute `hash:` in the same commit | RED (hash agrees with the file, not with the freeze) |

**Harness rows.** Suite edit: replace `verify-freeze` with a stub that always exits 0 — the suite must go RED (the RED fixtures above are the negative control, with a count floor on RED and must-PASS fixtures so `0 passed, 0 failed` cannot exit 0). Must-PASS non-canonical inputs: a YAML-reformatted block with equal canonical fields; a rebased branch with new SHAs and the same ordering.

**Anchor.** The stored `hash:` is self-consistent by construction, so it proves nothing alone. What lives outside the HEAD tree is the freeze commit's content in git history, which a one-commit edit of block-plus-hash cannot rewrite (row 6). History rewriting and forged `approved_by` are not stopped; ADR-274 names them as the residual. This guard is tamper-evident, not tamper-proof.

### Guard 2 — Must-fail baseline

**Property.** A check is accepted for freezing only if, run in the sandbox against the pre-work tree, the command actually ran and did not pass.

**Assembly.** Baseline runs enter only through `soleur:preflight --founder-check-baseline` into Check 13 baseline polarity; the single decision chokepoint is `founder-check.py classify(rc, stdout, expected, polarity, creates, target_present)`, used by both polarities. The INVALID set (rc 6, 7, 28, 124, 126, 127, sandbox error) is defined once, in `classify`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Baseline command that already passes (`printf ok`, expected `ok`) | RED (VACUOUS) |
| 2 | Baseline with bwrap absent — the guard's own dispatch must not report a "failed as expected" for a command that never ran | RED (SKIP-NOSANDBOX, capture refused) |
| 3 | rc 127 for a target not listed in `creates:` | RED (INVALID) |
| 4 | A `creates:` path that already exists in the tree at freeze (a stub) | RED |
| 5 | A second block whose baseline fails after a compliant first block passed baseline | RED (more than one block) |

**Harness rows.** Suite edit: make `classify` return FAILED-AS-EXPECTED unconditionally — the suite must go RED. Must-PASS non-canonical: a `grep` for a string not yet present (a legitimate fail), and an absent-by-design target listed in `creates:`.

**Anchor.** The baseline outcome is self-reported in the log. The outside anchor is ordering: the baseline log row's `tested_sha` must not be later than the freeze commit's first-code ordering (checked in `verify-freeze`), and `classify` re-derives the verdict from the logged rc and `output_sha256` rather than trusting the stored outcome.

### Guard 3 — Override only from an interactive answer

**Property.** `OVERRIDDEN` and `CONFIRMED-CHANGE` are written only after an interactive founder answer in the session; headless and one-shot runs cannot produce them.

**Assembly.** Every writer of a log outcome: the `founder-check.py log` subcommand (chokepoint) invoked from Check 13's interactive branch; the headless branch; the baseline mode. `log` refuses those two outcomes without `--interactive-answer` and `--reason`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `log --outcome OVERRIDDEN` without `--interactive-answer` | RED |
| 2 | Headless run with a failing check | RED if outcome is anything other than STOPPED-AWAITING-FOUNDER |
| 3 | Check 13's headless branch gains the token `OVERRIDDEN` | RED (test greps the section split by branch) |
| 4 | `log` called twice for the same hash, second with a rewritten first row | RED (append-only) |

**Harness rows.** Suite edit: drop the `--interactive-answer` check — the suite must go RED. Must-PASS: an interactive OVERRIDDEN with a reason.

**Anchor.** None outside the commit: an agent can pass the flag itself, so this control makes the override legible and attributable (logged, flagged in the table, visible in the PR diff), it does not authenticate the founder. ADR-274 says so; it must not be described as authentication.

### Guard 4 — Single sandbox chokepoint

**Property.** The approved check text runs only inside the one sandbox block defined in preflight Step 10.5.

**Assembly.** Every fence in `preflight/SKILL.md` that runs a command (Step 10.5 and Check 13's reference to it), every code path in `founder-check.py`, and every sandbox-argument variable (`BWRAP_ARGS`, `GIT_BIND`, `BWRAP_PROC`, the final invocation line). The chokepoint is Step 10.5; Check 13 and the script hold none of it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a `BWRAP_ARGS=(` array inside the Check 13 section | RED |
| 2 | `founder-check.py` gains `subprocess`/`os.system` execution of the command | RED |
| 3 | Check 13 executes `bash -c "$CMD"` directly instead of referencing Step 10.5 | RED |
| 4 | A second `BWRAP_ARGS=(` appended after a compliant first anywhere in the file | RED (count must stay 1) |

**Harness rows.** Suite edit: delete the count assertion — the integrity suite's own floor must report the missing assertion. Must-PASS: a Check 13 section that mentions the word "bwrap" in prose only (the anchor is the assignment syntax, not the bare token, per `cq-assert-anchor-not-bare-token`).

**Anchor.** The assertion lives in a test file outside the changed SKILL.md; one diff that edits both is possible, so the existing `lint-window-closure-assertion.py` declaration and the review-time closure-assertion bullet carry the independent half.

## Dependencies & Risks

- **Skill body ceilings are the binding constraint**, not the description budget; the plan stays inside them by using reference files and by editing nothing in qa/ship/brainstorm.
- **Public-repo leakage** of `text`, `command` and output prefix: mitigated by the scrub, hash-only fallback and the capture-time warning; the gdpr-gate review runs on this plan (trigger: brand-survival `single-user incident` and a new committed artifact).
- **Stale pass window** between preflight (Phase 5.4) and Phase 5.5's code-mutating gates: recorded via `tested_sha`; any back-edge re-runs preflight in full.
- **One-shot gives no founder to ask.** Headless runs never create a block and never override; a headless run whose plan already carries a block stops on failure. The most common autonomous path therefore skips Check 13 unless an interactive plan session captured a check earlier. This is stated plainly in the banner and the ADR, not hidden.
- **Check 13 cannot be tested for real bwrap in CI containers** where user namespaces are unavailable; `classify` and `verify-freeze` are tested without a sandbox, and the end-to-end run is a Phase 6 manual-free trace on this host.

## Sharp Edges

- A `founder_check` block is *data the plan skill must preserve*, not a template to regenerate. Any skill that rewrites a plan must reinsert it from the freeze commit verbatim.
- Never describe Check 13 or the sandbox as a security boundary; it bounds legibility and credential reach, and keeps network egress and arbitrary in-sandbox code (ADR-175).
- Pass wording is a contract: the three banned words and the exact pass sentence are pinned in `founder-check.py` constants and the CLO reviews them.
- A plan whose `## User-Brand Impact` section is empty or placeholder-only fails deepen-plan Phase 4.6.
- The ADR ordinal is provisional; on any renumber, sweep this plan, `tasks.md` and every AC that names it.

## Deferrals (tracked)

- Brainstorm-side prompt (needs ceiling headroom in `brainstorm/SKILL.md`, a separate reviewed ceiling PR).
- Multiple checks per plan, PR-body labels and a `founder-override` PR label, pre-supplied block for headless runs (needs `ship/SKILL.md` ceiling surgery).
- Hosted Command Center capture: out of scope, waits on #9620.
