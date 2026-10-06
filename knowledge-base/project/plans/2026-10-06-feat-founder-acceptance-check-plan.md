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
| FR5: a separate step runs it "from the committed text" | Preflight's Check 10 resolves the plan from a regex over the PR body, which the agent can edit | Check 13 resolves the plan by `git log -S'founder_check:'` over `origin/main..HEAD` (plans dir), never the PR body or a frontmatter key |
| Brainstorm: "CTO read only part of ADR-229" | Full read (504 lines): no change needed | See Q(e) |

## Answers to the plan-stage questions

**Q(a) — qa or a new preflight-style check?** A new **preflight Check 13**. qa has 8 bytes of body headroom and runs Playwright/API scenarios under a different authority. Preflight is uncapped, already owns the sandbox, the verb gate, the headless "FAIL aborts, no prompt" contract and the Phase 2 aggregate, and runs at ship Phase 5.4 on both the interactive and the one-shot path. A baseline mode (`--founder-check-baseline`) reuses the same Check 13 in must-fail polarity before work.

**Q(b) — how the frozen text survives plan amendment.** Four rules.

1. *Find the block narrowly.* Check 13 reads only the first fenced block inside the `## Acceptance Criteria` section of plans touched by this branch (`git diff --name-only origin/main...HEAD -- knowledge-base/project/plans/`, plus a plan already present at `git merge-base origin/main HEAD`). It never matches by `branch:` frontmatter (813 of 1,690 plans carry no `branch:` key) and never reads the plan path from the PR body. A `founder_check:` quoted under any other heading (this plan's own `## Design`, ADR-274, the reference file, fixtures) is ignored. Two plans each carrying a block, or a plan whose realpath leaves `knowledge-base/project/plans/`, is FAIL. Check 13 has its own resolver; the shared plan-file resolution strips fenced blocks and cannot be reused.
2. *Freeze = the earliest reviewed copy.* If the plan already carries the block at `git merge-base origin/main HEAD`, that copy is the freeze (it was reviewed on main). Otherwise the freeze is the earliest commit in `origin/main..HEAD` whose plan carries the block under that heading. The freeze should precede the first commit that touches anything outside `knowledge-base/`. A violation (a plugin edit that precedes the plan commit, as on this very branch) is **not a hard FAIL**: it takes the same stop-and-ask path as a change, so a legitimate mixed history is answered by the founder instead of by a heuristic.
3. *Compare canonical fields, not bytes.* HEAD's `kind`, `text`, `command`, `expected`, `creates`, `pins` are compared to the freeze. Reformatting passes. Any edit, or an ordering violation, is `CHANGED-SINCE-APPROVAL` and stops to ask: restore the frozen text, or accept anyway (`OVERRIDDEN`, one-line reason, both texts logged). Headless it is FAIL. Freeze exists but no block at HEAD is FAIL, never SKIP. A deliberate mid-work change of the check is therefore an override, never a silent edit; re-running `soleur:plan` on a branch that already carries a freeze **imports the block verbatim and does not re-ask**.
4. *Who wrote it.* A block executes without a prompt only when its authorship anchors to the local operator: the freeze commit's author email equals `git config user.email`, and, when a PR exists, the PR author's login equals `gh api user --jq .login`. Otherwise the block is `UNTRUSTED`: interactively Check 13 shows the exact command and asks before running; headless it is FAIL and never executes. This closes the path where a contributor's PR head carries a self-consistent plan, hash and freeze, and the operator's own preflight would run it (Check 10 is path-gated to sensitive diffs; Check 13 is not).

This is tamper-*evident*, not tamper-proof. The authorship anchor compares identity strings that the operator's own agent can also write, and an agent that rewrites branch history is not stopped by comparisons it also controls. The ADR names those residuals (same class as ADR-175's PR-head circularity); the log makes every difference visible in the PR diff.

**Q(c) — fail / override flow** (spec-flow analysis run; its decisions and the plan-review findings are folded in).

| State | Detection | Check 13 result | Interactive | Headless / one-shot |
|---|---|---|---|---|
| No block, no freeze evidence | resolver finds none | **SKIP** — banner "No founder-stated check was defined. Nothing was run on your behalf." | continue | continue (same banner) |
| Freeze evidence, no block at HEAD | history vs plan | **FAIL** | stop | abort |
| More than one block, two plans, or a symlinked plan | resolver | **FAIL** | stop | abort |
| `UNTRUSTED` authorship | author anchor | no run | show exact command, ask before running | **FAIL**, never executes |
| Differs from freeze, or ordering violation | canonical compare | **CHANGED-SINCE-APPROVAL** | restore / accept anyway (`OVERRIDDEN`) | **FAIL** |
| `kind: judgement` | block | **NEEDS-YOUR-EYES** — evidence shown, founder answers yes/no; yes logs `FOUNDER-CONFIRMED` (the founder, not a command, decided), no enters the FAILED row | founder decides | **FAIL** (`STOPPED-AWAITING-FOUNDER`) — an agent never decides |
| bwrap absent / cannot establish | Step 10.5 probe | **SKIP-NOSANDBOX** | "Your check did not run on this host. Continue without it?" yes/no, logged | block present: **FAIL** (`STOPPED-AWAITING-FOUNDER`); no block: SKIP |
| Ran, returned success, `expected` present | classify | **PASSED** — aggregate-row label "Founder check: ran, returned success against `<sha>`" (never a bare PASS); exact command and `expected` printed beside it | continue | continue |
| Ran, non-zero or `expected` absent | classify | **FAILED** | retry / restore-or-change the check / accept anyway | **FAIL** — `STOPPED-AWAITING-FOUNDER`; never auto-overridden |
| rc 124, 126 or 127; or rc 6, 7 or 28 when the first token is `curl`; or the sandbox-health control fails | classify | **INVALID** (tooling, not a result) | retry / change / accept anyway | **FAIL** |
| Founder picks "accept anyway" | interactive answer + one-line reason | **OVERRIDDEN** | recorded, continue | impossible |

**Roll-up into the overall verdict** (preflight Phase 2, uncapped; `ship` consumes only "any FAIL aborts, all PASS or SKIP continues"): ran-success and FOUNDER-CONFIRMED roll up as PASS; OVERRIDDEN rolls up as PASS-with-flag and its row is printed; SKIP, SKIP-NOSANDBOX and the no-block banner roll up as SKIP; FAIL and the headless stops roll up as FAIL. Retries are unbounded (the founder and the agent control both, so a cap protects nothing) but every attempt is logged with `attempt_n`, and a pass after failures prints "PASSED on attempt N after M failures". The log is a working-tree artifact: on the abort path ship stops before Phase 6 and the failure row may never be committed, so the log is evidence, not an authority.

**Stale-pass window.** Preflight runs at ship Phase 5.4; Phase 5.5 gates can mutate code and the Phase 7 behind-sync merges `main` afterwards, and neither is a back-edge. The pass wording, the aggregate row and the log row therefore name the commit ("against `<sha>`"), so a reader sees which tree was tested; the ADR records the window.

**Q(d) — does the skill-description budget allow the prompt text?** The description budget (2413/2413, headroom 0) is not the constraint: it counts `description:` frontmatter and this plan edits none. The real constraint is the **body ceilings** above. So the prompt text lives in a new `plan/references/plan-founder-check.md` (not a SKILL.md body) with a single pointer line in `plan/SKILL.md` of at most 130 bytes (136 available); `work/SKILL.md` and `brainstorm/SKILL.md` are not touched.

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
  creates: []                # optional repo-relative DATA paths the work will create (only with non-interpreter verbs)
  pins: {}                   # path -> git blob sha of each existing repo script the command names (interpreter verbs only)
  approved_by: ""            # recorded from the interactive answer
  approved_at: ""            # UTC date
  hash: ""                   # sha256 over canonical {kind,text,command,expected,creates,pins}; an identity shown in the log, NOT the integrity control (the freeze-commit comparison is)
```

Rules enforced by `founder-check.py` (not prose): first token on `PROBE_VERB_ALLOWLIST` via `probe-verb-gate.sh`; **no script indirection the work could author** — an interpreter verb (`bash`, `python3`, `node`, `bun`) is accepted only when every repo-relative script it names already exists at freeze and is recorded in `pins:` by git blob sha (a `pins` change after freeze is a change like any other), and `creates:` is accepted only with non-interpreter verbs (`curl grep rg jq printf git`); a check that runs a script the agent writes is the agent certifying itself, which is the failure ADR-175 names; the Step 10.5 shell-active-token reject; no `credentials_required` (a check needing credentials becomes `kind: judgement`); `expected` is **one exact literal substring** (no Check 10 OR-tokenisation); a single block per plan in v1.

### Result wording (single source: constants in `founder-check.py`, pinned by tests, CLO-reviewed)

- Pass: "Your check passed. This shows only that the check you wrote ran and returned success against <sha>. It does not confirm the work is correct, complete or safe. Review the result before relying on it." Judgement checks the founder answered yes use their own pinned sentence: "You confirmed this by looking. No command ran for it."
- First-use notice, shown at **every capture** on one screen with the leakage warning: "A vague, wrong or unsafe check can pass broken work or run actions you did not intend. Read what will run before it runs. One check does not cover everything. The text and command you approve are committed to this repository."
- The no-block banner and the no-sandbox line are pinned constants too, and the CLO reviews all four strings.
- Never the words "verified", "proven" or "safe". Passes and failures are shown with equal prominence: exact command, UTC time, rc, and the full output in the terminal only.

### What is committed (leakage rule)

`knowledge-base/project/specs/<branch>/founder-check-log.md` is append-only and records, per attempt: kind, command, rc, outcome, `attempt_n`, `tested_sha`, block hash, UTC time and `output_sha256`. **No output text is ever committed** — a regex scrubber for secret shapes has false negatives, and a false negative is the single-user leak. The full output is shown in the terminal only (spec FR6 asks that the result shows the output to the founder, not that it is committed). At capture the founder is told, on the same screen as the first-use notice, that `text` and `command` are committed to the repository and that one check does not cover everything.

## Implementation Phases

Test-first (`cq-write-failing-tests-before`): Phases 1 and 2 are RED then GREEN. Phase 0.3 comes first because it can change the scope. Phases 1–3 are the gate; Phases 4–5 are capture and decision record. The gate is inert without capture, and capture is a lie without the gate, so they ship together; the boundary is the split seam if the work grows (Scope Check, Split Assessment).

### Phase 0 — Preconditions

- 0.1 Re-verify the next free ADR ordinal against `origin/main` (`git ls-tree --name-only origin/main knowledge-base/engineering/architecture/decisions/`).
- 0.2 Re-measure body ceilings and the description budget; record numbers in the PR body.
- 0.3 **Dogfood before building:** draft five realistic founder checks (a grep on a rendered page, a `curl` status, a `jq` over a JSON file, a new-file existence check, a "looks right" judgement) and run each through Step 10.5 as-is. Record how many classify INVALID or judgement because of the 15-second cap, the read-only repo, `HOME=/tmp` or the verb list. If more than three of five cannot be expressed as a runnable command, stop and bring the finding back to the operator before Phase 1 — the feature would be mostly judgement checks.

### Phase 1 — Failing tests and fixtures (RED)

- 1.1 `plugins/soleur/test/preflight-founder-check.test.ts` drives the production `founder-check.py` (not a TypeScript mirror) over `fixtures/founder-check/*.md` plus synthesized git histories built with `gitFixture()` (see plugin AGENTS.md "Test Fixture Conventions"; never a hand-rolled git env).
- 1.2 Fixtures (synthesized only, `cq-test-fixtures-synthesized-only`): valid block; reformatted-but-equal block; edited command; edited expected; deleted or renamed plan after freeze; two blocks; two plans each carrying a block; symlinked plan; block quoted under a non-AC heading; block committed with code; a learnings-only commit before the freeze; a plan already on `main`; `hash:` removed; `creates:` stub already present; `creates:` with an interpreter verb; interpreter verb with an unpinned script; pinned script edited after freeze; `credentials_required` present; trivial verb; judgement kind; rebase-changed SHAs; freeze authored by a different identity; a sandbox runtime error returning rc 1.
- 1.3 Register `preflight-founder-check.test.ts` in `preflight-check10-suite-integrity.test.sh` (its `SUITES` list, manifest and floor ratchets) so the new suite cannot be silently skipped, and add the Check 13 section assertion for Guard 4 (no sandbox assignment inside the section; the single-occurrence `BWRAP_ARGS=(` pin already lives in `preflight-discoverability-test.test.ts`, which is **not** edited). Extend `plan-skeleton-checkpoint.test.ts` to assert a plan carrying a `founder_check` block under `## Acceptance Criteria` still satisfies the completion predicate. Headless behaviour is tested through `founder-check.py log --mode headless`, not by grepping SKILL.md prose.
- 1.4 Run the suites; every new case must be RED for the right reason (script absent), recorded in the PR body.

### Phase 2 — `founder-check.py` (GREEN)

Stdlib-only Python at `plugins/soleur/skills/preflight/scripts/founder-check.py`, subcommands `verify` (resolve, parse, canonical hash, freeze comparison, authorship anchor, `pins` blob check), `classify`, `log` (`--mode interactive|headless`) and `summary`, plus the wording constants. It **never executes the founder command** (Guard 4) and does **not** re-implement the Step 10.5 shell-active-token reject (Check 13 applies Step 10.5's own reject; a second copy would drift). `classify` is a pure function of `(rc, stdout, expected, polarity, creates, target_present, sandbox_healthy)`, shared by baseline and acceptance polarity, so there is one decision chokepoint; any non-zero rc is a valid baseline fail when a listed `creates:` path is absent. `summary` reads the log and prints `founder-check: <N> rows` or `founder-check: no log`; the no-log case has its own test so the discoverability probe cannot be vacuous.

### Phase 3 — preflight Check 13

Edit `plugins/soleur/skills/preflight/SKILL.md` (uncapped, but 113 KB and read on every ship, so the bulk goes in a new `preflight/references/check-13-founder-check.md` linked from a short Check 13 section): add `### Check 13: Founder-Stated Check` after Check 12. **Check 13 runs Step 10.5 through a wrapper** (Risks: "Step 10.5 reuse is textual, by wrapper"): set `CMD`, define `sanitize`, run the fence inside `OUT=$( … )`, append `DT_RC` and `DT_STDOUT_SAFE`, hand rc and stdout to `founder-check.py classify`, and map the sandbox output to Check 13 outcomes via a table in the reference file; before any baseline fail counts, run the sandbox-health control (`true` must return rc 0). **Check 13 inside Phase 1 only classifies and returns an outcome**; the retry / change / accept-anyway prompt, the old-versus-new diff display and the confirm-change answer run in the Phase 2 "If any FAIL" branch, after the parallel checks finish, because a prompt cannot run inside a parallel check. `--founder-check-baseline` is a new argument next to `--headless` and **skips Checks 1–12 explicitly**. Also add the Phase 2 aggregate row (`ran-returned-success / FAIL / SKIP / SKIP-NOSANDBOX / OVERRIDDEN`), plus an extra closing line when the outcome is OVERRIDDEN ("Founder check OVERRIDDEN: <reason>") and a visible summary line when it is SKIP-NOSANDBOX ("your check did not run; ship continues"); the fast-path overview row ("never SKIPs on an empty cache; runs whenever a plan for this branch carries a `founder_check` block or freeze evidence"); the headless paragraph (Check 13 `SKIP-NOSANDBOX` and the no-block banner are always emitted, like Check 10's); the `--founder-check-baseline` mode; and a Sharp Edges entry. Check 13 runs Step 10.5 unchanged with `CMD` set to the founder command and emits the metadata-only marker `SOLEUR_FOUNDER_CHECK_RESULT outcome=… hash=… tested_sha=…` (no command text, no output).

### Phase 4 — Capture (plan side)

- 4.1 Create `plugins/soleur/skills/plan/references/plan-founder-check.md` (the only place the `founder_check:` YAML shape lives): the question, a one-sentence plain-language "what this will do" line the agent writes beside the literal command, the proposal/approval loop, vague-check rewrite or `needs-your-eyes`, the first-use notice, the capture-time leakage warning, the baseline invocation, the `creates:` and `pins:` rules and the warning that pipes, `&&`, `$VAR` and test-runner or build commands are rejected or hit the 15-second cap and the restricted PATH, that `soleur:plan` makes the **freeze commit immediately after a valid baseline** (before any later plan phase), that a `needs-your-eyes` check is recorded when no runnable form exists, headless behaviour (no question asked; no block written), and the import-on-rerun rule.
- 4.2 One pointer line in `plan/SKILL.md` (≤130 bytes). Verify with `python3 scripts/lint-skill-body-budget.py` against the merge base. If the line does not fit, trim an equal number of bytes elsewhere in the same file in the same edit; never raise a ceiling.
- 4.3 Add a one-line HTML-comment pointer under `## Acceptance Criteria` in the MINIMAL, MORE and A LOT templates of `plan-issue-templates.md` ("founder-stated check: see plan-founder-check.md"). **No empty `founder_check:` YAML stub in the templates**: a stub on every plan would read as a block with no freeze commit and FAIL every plan that does not use the feature.
- 4.4 `work/SKILL.md` is **not edited** (the gate, not a prose rule, enforces that the block is not changed; this saves 240 bytes of a ceiling that has almost none).

### Phase 5 — Decision record and architecture

- 5.1 ADR-274 (provisional) and the inline ADR-175 amendment (Architecture Decision, below).
- 5.2 `model.c4` and the generated `model.likec4.json`: edit the `contributor` description and the adjacent comment (Architecture Decision, C4 views), regenerate the JSON with `scripts/regenerate-c4-model.sh`; run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 6 — Verification

- 6.1 `bun test plugins/soleur/test/preflight-founder-check.test.ts plugins/soleur/test/preflight-discoverability-test.test.ts plugins/soleur/test/plan-skeleton-checkpoint.test.ts plugins/soleur/test/components.test.ts` and `bash plugins/soleur/test/preflight-check10-suite-integrity.test.sh`.
- 6.2 `python3 scripts/lint-skill-body-budget.py`, `python3 scripts/lint-guard-contract.py` on this plan, and the repo markdown lint.
- 6.3 Trace `soleur:ship` to confirm `specs/<branch>/founder-check-log.md` is staged by its existing artifact commit (Phase 6). If it is not, the fix is a one-line instruction printed by Check 13 ("commit this file"), not a commit made inside preflight.
- 6.4 CLO review of the final prompt, notice and result wording (spec acceptance criterion) before the PR leaves draft.

## Files to Create

- `plugins/soleur/skills/preflight/scripts/founder-check.py`
- `plugins/soleur/skills/plan/references/plan-founder-check.md`
- `plugins/soleur/skills/preflight/references/check-13-founder-check.md`
- `plugins/soleur/test/preflight-founder-check.test.ts`
- `plugins/soleur/test/fixtures/founder-check/` (fixture set, ~14 files; counted as one entry)
- `knowledge-base/engineering/architecture/decisions/ADR-274-founder-stated-acceptance-check-frozen-separately-executed.md`

## Files to Edit

- `plugins/soleur/skills/preflight/SKILL.md`
- `plugins/soleur/skills/plan/SKILL.md` (one pointer line, ≤130 bytes)
- `plugins/soleur/skills/plan/references/plan-issue-templates.md`
- `plugins/soleur/test/preflight-check10-suite-integrity.test.sh`
- `plugins/soleur/test/plan-skeleton-checkpoint.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-175-preflight-probe-execution-boundary.md` (inline amendment)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)

**Not edited, on purpose:** `qa/SKILL.md`, `ship/SKILL.md`, `brainstorm/SKILL.md`, `work/SKILL.md` (ceiling headroom of 8, 5, 125 and 240 bytes), `plugins/soleur/lib/workflow-fidelity.ts`, `.claude/workflow-transitions.json`, `skill-body-budget.json`, any `description:` frontmatter.

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
| `pins:` and the interpreter-verb rule | — | inferred — justification: a check that runs a script the agent writes during work is the agent certifying itself, the failure ADR-175 names; the hash alone cannot see it (plan-review P0) |
| authorship anchor and `UNTRUSTED` | — | inferred — justification: Check 13 is not path-gated, so a contributor's PR head carrying a self-consistent block would otherwise run on the operator's machine with no prompt (plan-review P0, security) |
| Step 10.5 wrapper and sandbox-health control | "Extend the plan acceptance field and the preflight Check 10 sandbox path." [brief] | asked |
| `creates:` field | — | inferred — justification: without it the commonest check ("the new script prints ok") can never be baselined, because the target is absent for the wrong reason; spec FR3's must-fail rule would otherwise reject it |
| INVALID classification | — | inferred — justification: a tooling failure (timeout, command not found) would otherwise count as a valid baseline fail, certifying a check that can never pass |
| per-attempt log (`attempt_n`) | — | inferred — justification: a pass after failures must be visible to the reader as such; retries themselves are uncapped because the founder and the agent control both |
| `founder-check-log.md` | "Show the exact command, the time and the output, and show passes and fails equally" [brainstorm] | asked |
| `kind: judgement` | "Judgement checks go to the founder as a yes/no with evidence" [brainstorm] | asked |
| `model.c4` contributor edit | — | inferred — justification: the C4 completeness mandate; the `contributor` description states the discoverability probe is the *one* PR-head artifact preflight executes, which Check 13 makes false |
| three test-file extensions (check-10 suite-integrity, discoverability, skeleton) | "Tests extend `plugins/soleur/test/preflight-discoverability-test.test.ts`, its fixtures under `fixtures/preflight-check-10/`, `plan-skeleton-checkpoint.test.ts` and `preflight-check10-suite-integrity.test.sh`" [spec TR3] | asked |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 14 entries (fixture set counted once) | Estimated changed lines: ~1,100 (about 450 are tests and fixtures, 100 ADR prose)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the line count crosses the threshold on mechanical test/fixture volume, not on scope; a split (gate in PR 1, capture + ADR in PR 2) was considered and rejected because the gate is inert without capture and a founder-facing prompt without the gate would claim a check that nothing runs. The Phase 3/Phase 4 boundary is the seam if work grows past this estimate.

## Acceptance Criteria

- [x] `soleur:preflight` Check 13 exists after Check 12, with the Phase 2 aggregate row, the roll-up rules (ran-success and FOUNDER-CONFIRMED = PASS; OVERRIDDEN = PASS-with-flag, row printed; SKIP, SKIP-NOSANDBOX and the no-block banner = SKIP; FAIL and headless stops = FAIL) and the fast-path overview row; it runs the founder command only through the Step 10.5 fence via the wrapper; `BWRAP_ARGS=(` still occurs exactly once in `preflight/SKILL.md`; Check 10's output is unchanged.
- [x] A plan with freeze evidence and no resolvable block returns FAIL, never SKIP, including when the plan file is deleted or renamed (fixtures + test).
- [x] An edit to `kind`, `text`, `command`, `expected`, `creates` or `pins` after the freeze is rejected; a pure YAML reformat of the same fields passes; a block quoted under a non-AC heading is ignored (Guard 1 rows 1, 4, 7).
- [x] An interpreter verb (`bash`, `python3`, `node`, `bun`) is accepted only with every named repo script present at freeze and pinned by git blob sha; editing a pinned script after the freeze is rejected; `creates:` with an interpreter verb is rejected (Guard 1 rows 5–6, Guard 2 row 5).
- [x] A rebased branch with new SHAs still passes; a learnings-only commit before the freeze does not fail it; a plan already on `main` is frozen at the merge-base copy; an ordering violation takes the stop-and-ask path, not a hard FAIL.
- [x] Re-running `soleur:plan` on a branch carrying a freeze imports the block and does not re-ask or drop it; the freeze commit is made immediately after a valid baseline.
- [x] A baseline that passes is `VACUOUS`; rc 124/126/127, rc 6/7/28 for `curl`, and a failed sandbox-health control classify as `INVALID`, never as a baseline fail or a pass; the baseline log row sits in the freeze copy and carries `rc` and `expected_matched`.
- [x] A block whose freeze author or PR author does not match the local operator is `UNTRUSTED`: headless FAIL with no execution; interactive shows the exact command and runs nothing before the answer.
- [x] `founder-check.py log --mode headless` refuses `OVERRIDDEN` and `FOUNDER-CONFIRMED`; an interactive override requires a reason; a headless run with a failing check yields `STOPPED-AWAITING-FOUNDER`; headless with an approved block and no sandbox is a FAIL.
- [x] The pass sentence, the judgement sentence, the first-use notice, the no-block banner and the no-sandbox line are constants matching this plan's text exactly; no output string contains "verified", "proven" or "safe"; the aggregate row reads "ran, returned success against `<sha>`" and never a bare PASS; the first-use notice is shown at every capture.
- [x] `founder-check-log.md` is append-only per `log`, holds only rc, outcome, `attempt_n`, `tested_sha`, hash, time, `output_sha256` and `expected_matched`, and no output text; a no-bwrap host reports "your check did not run on this host" and baseline capture is refused (judgement only).
- [x] `founder-check.py summary` prints `founder-check: <N> rows` over a populated log and `founder-check: no log` otherwise, each with its own test.
- [x] `python3 scripts/lint-skill-body-budget.py` is green against the merge base; `plan/SKILL.md` grew by at most 136 bytes; `work`, `qa`, `ship`, `brainstorm` and every `description:` are unchanged; the `components.test.ts` budget test still passes at 2413/2413; `preflight-founder-check.test.ts` is registered in the suite-integrity gate.
- [x] ADR-274 exists (ordinal re-verified against `origin/main`), the ADR-175 amendment is present, ADR-229 and `workflow-fidelity.ts` are unmodified, and the `model.c4` and regenerated `model.likec4.json` edits pass `c4-code-syntax`, `c4-render` and `c4-count-parity`.
- [x] `python3 scripts/lint-guard-contract.py` reports 4 entries for this plan.
- [ ] The CLO has reviewed the final prompt, notice, banner and result wording; no marketing, changelog or demo copy claims the feature.

> Implementation note (work phase): `brainstorm/SKILL.md` carries commit 820eb958fb (a +144 B surface-attribution edit from the brainstorm phase, before this plan was written, so the 140,875 B baseline above already includes it). The implementation made no edit to `work`, `qa`, `ship` or `brainstorm`. The CLO wording review (last item) needs the CLO agent and is still open.

## Test Scenarios

- Given a founder who answers the plan prompt with a check that already passes, when the baseline runs, then the plan reports VACUOUS and offers: strengthen the check, mark it needs-your-eyes, or record it as already true and drop it (a dropped check never reappears as a pass).
- Given an approved check and a finished feature, when ship runs preflight, then Check 13 reports PASSED with the exact pass wording, the command, the time and the output, and appends one log row.
- Given the check fails at ship in an interactive session, when the founder picks "accept anyway" and types a reason, then the table shows OVERRIDDEN, the log row says so, and nothing says "passed".
- Given a one-shot run whose plan carries a block and the check fails, when preflight runs headless, then the pipeline aborts with STOPPED-AWAITING-FOUNDER and no override is possible.
- Given `work` reformats the plan and edits `expected`, when Check 13 runs, then CHANGED-SINCE-APPROVAL shows both texts; interactive offers restore or accept anyway (OVERRIDDEN with a reason), headless fails.
- Given a contributor's PR head carries a plan with a self-consistent block, when preflight runs headless on the operator's machine, then the result is UNTRUSTED, nothing runs and the run fails; interactively the exact command is shown and nothing runs before the answer.
- Given a check of the form `bash scripts/new-check.sh` where the script is written by the work, when capture proposes it, then it is rejected (no pin exists at freeze) and the founder is offered a non-interpreter form or a judgement check.
- Given a macOS host, when capture starts, then the founder is told the check cannot run here and may only record a needs-your-eyes check.
- Verification of the PR itself (consumed by `soleur:qa`): **API verify:** `python3 plugins/soleur/skills/preflight/scripts/founder-check.py summary` expects the line prefix `founder-check:` (`no log` before any run).

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
    detection: founder-check.py verify compares canonical fields to the freeze commit and returns FAIL or CHANGED-SINCE-APPROVAL
    alert_route: Check 13 table row in the founder's session (layer 7)
  - mode: sandbox cannot be established so the check never ran
    detection: SKIP-NOSANDBOX line plus SOLEUR_FOUNDER_CHECK_RESULT outcome=SKIP-NOSANDBOX, stated as "your check did not run"
    alert_route: stdout in-session (layer 7), and the log row
  - mode: authorship does not anchor to the local operator (a contributor's PR head)
    detection: verify returns UNTRUSTED; interactive shows the command and asks, headless FAILs without running
    alert_route: stdout in-session (layer 7) and the log row

logs:
  where: knowledge-base/project/specs/<branch>/founder-check-log.md, committed to the founder's own repository
  retention: lives with the repository history

discoverability_test:
  command: python3 plugins/soleur/skills/preflight/scripts/founder-check.py summary
  expected_output: founder-check:
```

## Architecture Decision (ADR/C4)

### ADR

- **Create ADR-274** (provisional ordinal) "Founder-stated acceptance check: frozen, separately executed", terse shape, `related_adrs: [ADR-175, ADR-229]`. One ADR carries everything: the freeze-copy anchor and why the hash alone is self-certification; the pinned-script rule and why a script the agent writes is the agent certifying itself; the authorship anchor and what it does and does not authenticate; the outcome vocabulary (VACUOUS, INVALID, FAILED, PASSED, FOUNDER-CONFIRMED, OVERRIDDEN, UNTRUSTED, STOPPED-AWAITING-FOUNDER); the ADR-229 full-read verification (and that "change the check" mid-ship is the declared `work → plan` edge); the Linux-first statement; the stale-pass window; the headless reach gap; and the named residuals (history rewriting, the operator's own agent forging identity strings, shared host loopback #7412). Alternatives are cited from this plan's Cut List, not restated.
- **Amend ADR-175** with a short inline blockquote under its Layer 1 heading, in that file's `> **YYYY-MM-DD amendment (#N).**` convention, pointing to ADR-274: Layers 1 and 2 apply unchanged to a founder-approved command; approval is a consent step, not an authority grant; credentialed checks get no waiver path.
- **ADR-229: no change** (Q(e)); the ADR-274 text says so with the evidence.

### C4 views

All three of `model.c4`, `views.c4`, `spec.c4` were read in full for this section, not grepped for the feature noun.

- (a) *External human actor*: the `founder` actor already exists and is modelled as the workspace Owner running Soleur skills in the CLI. The `contributor` actor (untrusted PR author) is relevant because a contributor's PR head can carry a plan with a self-consistent `founder_check` block (Guard 3's authorship anchor and show-before-run answer this).
- (b) *External system / vendor*: none added; the check runs locally in the existing bwrap sandbox, no new integration edge.
- (c) *Container / data store*: none; the log is a file in the founder's repository.
- (d) *Actor↔surface access relationship*: unchanged for `founder`; for `contributor`, the one-artifact statement changes.
- **Edit `model.c4`:** the `contributor` element's description says "The one PR-head artifact preflight executes on the operator's own workstation — a plan-declared discoverability probe", and the comment above it says "preflight Check 10 executes a plan-declared probe". Both become false with Check 13, which executes a second PR-head artifact (a plan-declared `founder_check` command) in the same sandbox. Reword both to "plan-declared probes and checks" with no count, so the sentence does not go stale again, and keep the comment and description in agreement (they disagreed once, #7393 review). No `views.c4` change: no element is added and `contributor` already renders.
- Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (no cardinality moves; the run proves it).

### Sequencing

The ADR describes the target state and is authored in this PR, not postponed. Status `accepted` at merge; no soak.

## Guard Contract

### Guard 1 — Frozen-block integrity

**Property.** A `founder_check` block that passes Check 13 equals, on its canonical fields, the block in the freeze copy (a reviewed copy on `main`, else the earliest commit on the branch), or the founder accepted each difference as an override.

**Assembly.** Every path by which block text reaches the gate: the plan file(s) touched by the branch, the freeze copy in git history (found by `git log -S'founder_check:'` over the plans directory, independently of whether the plan still resolves, so deleting or renaming the plan cannot turn FAIL into SKIP), the pinned-script blob shas, and every writer of the plan — `soleur:plan` re-run, `deepen-plan`, `plan-review`, `work`, review fix commits. The one chokepoint is `founder-check.py verify`, the sole parser and comparer, used by baseline and acceptance polarity alike; SKILL.md prose holds no second comparison.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Edit `command` in the HEAD block after the freeze | RED (CHANGED-SINCE-APPROVAL; headless FAIL) |
| 2 | Plan deleted, renamed or stripped of its block while a freeze exists in history (the guard's own dispatch finding "0 blocks") | RED (FAIL, never SKIP) |
| 3 | Add a second, differing block under `## Acceptance Criteria` after a compliant first | RED |
| 4 | Edit `expected` and recompute `hash:` in the same commit | RED (the hash agrees with the file, not with the freeze) |
| 5 | Edit a pinned script after the freeze (interpreter verb) | RED (blob sha differs) |
| 6 | Interpreter verb naming a script not in `pins:`, or `creates:` combined with an interpreter verb | RED |
| 7 | Block quoted under a non-AC heading while a real block exists elsewhere | GREEN (must-PASS fixture: quoted blocks are ignored) |

**Harness rows.** Suite edit: replace `verify` with a stub that always exits 0 — the suite must go RED (a count floor on RED and on must-PASS fixtures means `0 passed, 0 failed` cannot exit 0). Must-PASS non-canonical inputs: a YAML-reformatted block with equal canonical fields; a rebased branch with new SHAs; a learnings-only commit before the freeze; a plan already on `main`.

**Anchor.** `hash:` is self-consistent by construction and proves nothing alone (it is an identity shown in the log). What lives outside the HEAD tree is the freeze copy in git history, which a one-commit edit of block-plus-hash cannot rewrite (row 4), and the authorship anchor (Guard 3). History rewriting and the operator's own agent forging identity strings are not stopped; ADR-274 names them. Tamper-evident, not tamper-proof.

### Guard 2 — Must-fail baseline

**Property.** A check is accepted for freezing only if, run in the sandbox against the pre-work tree, the sandbox was healthy, the command actually ran, and it did not pass.

**Assembly.** Baseline runs enter only through `soleur:preflight --founder-check-baseline` (which runs Check 13 alone, flag stripped like `--headless`). The decision chokepoint is `founder-check.py classify(rc, stdout, expected, polarity, creates, target_present, sandbox_healthy)`, shared by baseline and acceptance; the INVALID set (rc 124, 126, 127; rc 6, 7, 28 only for a `curl` first token; sandbox-health control failure) is defined once, there. A sandbox-health control (`true` must return rc 0 inside the same sandbox) runs before a baseline fail counts, because bwrap's own runtime errors surface as an ordinary rc 1 and would otherwise certify as "failed as expected".

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Baseline command that already passes (`printf ok`, expected `ok`) | RED (VACUOUS) |
| 2 | Baseline with bwrap absent (the guard's own dispatch must not report "failed as expected" for a command that never ran) | RED (SKIP-NOSANDBOX, capture refused) |
| 3 | Sandbox runtime error returning rc 1 (health control fails) | RED (INVALID, not a baseline fail) |
| 4 | rc 127 for a target not listed in `creates:` | RED (INVALID) |
| 5 | A `creates:` path that already exists at freeze (a stub), or `creates:` with an interpreter verb | RED |

**Harness rows.** Suite edit: make `classify` return FAILED-AS-EXPECTED unconditionally — the suite must go RED. Must-PASS non-canonical: a `grep` for a string not yet present (a real fail); any non-zero rc for a target absent and listed in `creates:` (a python rc 2 or node rc 1 included).

**Anchor.** The baseline outcome is self-reported. The outside anchor is content, not SHA ordering (SHAs change on rebase): the freeze copy's own `founder-check-log.md` must contain a baseline row whose block hash equals the block's, and the row records `rc` and a derived `expected_matched` boolean so `classify` can re-derive the verdict from `(rc, expected_matched)`. The boolean is itself self-reported; `tested_sha` is informational only.

### Guard 3 — Consent before run; override only interactive

**Property.** A founder-check command runs only if its authorship anchors to the local operator or the operator confirmed the exact command interactively in that session, and `OVERRIDDEN` / `FOUNDER-CONFIRMED` are written only in interactive mode.

**Assembly.** Every writer of a log outcome and every path to execution: `founder-check.py verify` (which returns `UNTRUSTED` unless the freeze commit's author email equals `git config user.email` and, with a PR, the PR author login equals the authenticated login), the `log` subcommand (chokepoint for outcomes, taking `--mode interactive|headless`), the interactive branch, the headless branch and baseline mode.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `log --mode headless --outcome OVERRIDDEN` (or `FOUNDER-CONFIRMED`) | RED (refused) |
| 2 | `log --mode interactive --outcome OVERRIDDEN` without a reason | RED |
| 3 | A plan whose freeze commit is authored by a different identity, run headless | RED (UNTRUSTED, no execution) |
| 4 | The same plan interactive: the exact command is shown and nothing runs before the answer | RED if it runs first |

**Harness rows.** Suite edit: delete the `--mode` refusal — the suite must go RED. Must-PASS: an interactive OVERRIDDEN with a reason; a block authored by the local identity.

**Anchor.** None outside the commit: the operator's own agent can pass `--mode interactive` and can write identity strings, so this control makes an override legible, attributable and visible in the PR diff; it does not authenticate the founder, and ADR-274 must not describe it as authentication. Its real protective value is against a *contributor's* PR head.

### Guard 4 — Single sandbox chokepoint

**Property.** The approved check text runs only inside the one sandbox block defined in preflight Step 10.5.

**Assembly.** Every fence in `preflight/SKILL.md` that runs a command (Step 10.5 and Check 13's wrapper around it), every code path in `founder-check.py`, and every sandbox-argument variable (`BWRAP_ARGS`, `GIT_BIND`, `BWRAP_PROC`, the final invocation line). The chokepoint is Step 10.5; Check 13's wrapper runs that fence inside a command-substitution subshell (so its `exit` branches end only the subshell) and the script holds none of it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Add a `BWRAP_ARGS=(` array inside the Check 13 section | RED |
| 2 | `founder-check.py` gains `subprocess` / `os.system` use on the command | RED |
| 3 | Check 13's wrapper replaces the Step 10.5 fence with a direct `bash -c "$CMD"` | RED |

**Harness rows.** Suite edit: delete the Check 13 section assertion — the integrity suite's floor must report the missing assertion. Must-PASS: a Check 13 section that mentions "bwrap" in prose only (the anchor is the assignment syntax, not the bare token, per `cq-assert-anchor-not-bare-token`).

**Anchor.** The `BWRAP_ARGS=(` single-occurrence pin already exists in `preflight-discoverability-test.test.ts` and `lint-window-closure-assertion.py` declares its window; those are the independent half and are not duplicated here.

## Dependencies & Risks

- **Skill body ceilings are the binding constraint**, not the description budget; the plan stays inside them by using reference files and editing nothing in qa, ship, brainstorm or work.
- **Public-repo leakage:** `text` and `command` are committed (the founder is told at capture); command *output* is never committed, only its hash, rc and a boolean. The gdpr-gate review runs on this plan (trigger: brand-survival `single-user incident` and a new committed artifact).
- **Contributor PR heads.** Check 13 is not path-gated like Check 10, so it widens the execution trigger on a checked-out PR head. Guard 3's authorship anchor and the interactive show-before-run close the headless and no-prompt paths; the shared host network namespace (#7412) is unchanged and is not claimed closed.
- **Stale-pass window** between preflight (Phase 5.4) and Phase 5.5's code-mutating gates and the Phase 7 behind-sync: the pass wording, the aggregate row and the log row name the commit tested.
- **One-shot gives no founder to ask.** Headless runs never create a block and never override; a headless run whose plan already carries a block stops on failure, on `UNTRUSTED` and on no-sandbox. The most common autonomous path therefore skips Check 13 unless an interactive plan session captured a check earlier. The banner and the ADR say so plainly. Reach is a deferral issue (below), not hidden.
- **Linux-first.** bwrap is Linux-only (ADR-175 Consequences), so on macOS the check cannot run and capture is refused except as a judgement check. ADR-274 states this; an un-sandboxed run on those hosts would contradict ADR-175's fail-closed posture and is not offered.
- **Hosted path.** `plugins/soleur/` is also vendored into the hosted image. Check 13's marker is metadata-only (outcome, hash, `tested_sha`), safe for the Bash marker extractor; hosted capture and any hosted claim are out of scope and wait on #9620. A hosted agent that reaches Check 13 finds no block (capture is interactive plan only) and prints the SKIP banner.
- **Step 10.5 reuse is textual, by wrapper.** Step 10.5 is a fenced block an agent follows, not a callable. Check 13's wrapper sets `CMD`, defines `sanitize`, runs the fence inside `OUT=$( … )` so the `exit 0` branches end only the subshell, appends `DT_RC` and `DT_STDOUT_SAFE` to the subshell output, and then maps that output (a table in the reference file) to Check 13 outcomes while dropping the Check 10-labelled sentinel lines, so fleet telemetry does not count Check 13's dark runs as Check 10's. The alternative — extracting the sandbox into a script — conflicts with the pinned inline `BWRAP_ARGS` and `lint-window-closure-assertion.py` and is **not** taken here; it is the operator's call if the wrapper proves brittle in Phase 0.3 or Phase 3.
- **Most real checks may be judgement checks.** The verb list has ten entries, no pipes, a read-only repo and a 15-second cap; `npm test | tail`, `pytest` and `make` are rejected or hit those limits. Phase 0.3 measures this before building, and capture warns the founder before approval.

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
