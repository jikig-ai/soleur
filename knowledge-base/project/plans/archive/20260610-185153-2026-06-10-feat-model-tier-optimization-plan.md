---
title: "feat: Model-tier optimization via workflow call-site tiering"
type: feat
date: 2026-06-10
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: "#3791"
spec: knowledge-base/project/specs/feat-model-tier-optimization/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-06-10-model-tier-optimization-brainstorm.md
---

# feat: Model-tier optimization via workflow call-site tiering

> Plan v3 — revised 2026-06-10 after 5-agent plan review (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer ×2). v2→v3: TIER_PINS map deleted (4-reviewer convergence: contradicted AC2); FR4 Inngest registry cut to follow-up #5106 (both panels fired — delete over fix; dissolved Kieran P0 + spec-flow N2/N3/N4); Phase 6 collapsed to single tiered arm (TR5 narrowing recorded); standing pin-allowlist test added (architecture P1 — the mechanical never-downgrade gate); `VALID_MODELS` + `fable`; ADR-053 lifecycle content; FR5 single-field; AC mechanics fixed.

## Overview

Fable 5 ($10/$50 per MTok) is 2× Opus 4.8, 3.3× Sonnet 4.6, and 10× Haiku 4.5. Soleur currently runs every subagent at the session model (`model: inherit` on all 66 agents; no `opts.model` in any of the 8 workflow scripts), so a Fable 5 session pays top-tier rates for mechanical work: diff classification, GitHub-issue filing, comment fetching, commit-message generation, report assembly. This PR pins explicit cheaper models at 12 **mechanical** workflow call sites, pins the unpinned per-PR CI review action, adds model attribution to the existing per-spawn token telemetry, adds a standing pin-allowlist test, and amends the Model Selection Policy — all judgment, review, security, and compliance paths stay on `inherit`.

Scope: `plugins/soleur` + `.claude/hooks` + `.github/workflows` + policy docs. The web-platform Inngest registry was reviewed out to **#5106** (independent deploy surface, zero shared code).

Closes #3791 (deferred 2026-05-15; its "pricing change" re-evaluation trigger fired with Fable 5). Complement: #2030 (advisor tool, web platform). Deferred follow-ups: #5099 (BYOK ledger `model` column + legal lockstep), #5100 (`model-launch-review` skill), #5106 (Inngest registry).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality (verified 2026-06-10) | Plan response |
|---|---|---|
| "No per-agent token telemetry exists" (CTO + CFO leader assessments) | `.claude/hooks/agent-token-tee.sh` (#3494) records per-spawn token envelopes to `.claude/.session-tokens.jsonl`; consumer: compound Phase 1.6 `token-efficiency-report.sh` (selects keys by name under `select(.schema == 1)`) | FR5 narrows to *model attribution* (additive `model` key), not new telemetry infra |
| "No in-repo doc establishes whether workflow `agent()` accepts `model`" (repo research) | Harness Workflow tool contract: `opts.model` enum `sonnet\|opus\|haiku\|fable`. BUT no empirical capture exists of a Workflow-spawned PostToolUse payload (the #3494 capture predates workflows; `tool_input` showed `{description, prompt, subagent_type}` only) | Phase 0 empirical capture gates FR5's field mapping (spec-flow P0) |
| "~14 mechanical workflow steps" | 12 pinnable call sites after reconciliation; review `verify`/`concur` excluded (judgment); agent-native-audit excluded per the platform's own sonnet→opus upgrade precedent (`cron-agent-native-audit.ts:30-31`); `resolve-parallel` `plan` (:272) exempt (judgment). All 27 `agent()` sites across the 8 files accounted for (Kieran-verified) | FR1: 12 pins + complete exemption list + standing allowlist test |
| Spec FR4 "Inngest cron tier registry" | 16 cron/event files carry literals (not 15 — `event-ship-merge.ts` included) + `agent-on-spawn-requested.ts` `MODEL_PRICING` (2 keys only — a registry parity AC is unsatisfiable without an unstated opus pricing entry) | **Deferred to #5106** with corrected facts (spec FR4 updated) |
| Spec TR5 "tiered vs untiered side-by-side" | Two-arm comparison is non-probative at n=1 (nondeterministic agents), cannot attribute JSONL rows to arms, and costs a full Fable-rate review run | **Narrowed to single tiered arm** (spec TR5 updated; spec-flow P2.9 disposition) |
| Constitution line 20 enum `inherit\|haiku\|sonnet\|opus`; `components.test.ts:13` `VALID_MODELS` same | Harness enum includes `fable`; adding it to the constitution alone would create a doc-says-X / CI-says-Y trap | Phase 1 updates BOTH (architecture P2) |
| Issue #3791 premise | OPEN, artifacts linked 2026-06-10 | Tracking issue; PR body `Closes #3791` |

Premise validation: all cited artifacts verified live this session; pin/exemption line numbers verified against current source by two independent review agents.

## Proposed Solution

### Phase 0 prerequisite — empirical PostToolUse capture (gates FR5/AC7)

Capture one pinned-spawn PostToolUse payload: run a throwaway 1-agent workflow (`agent(prompt, { model: 'haiku', label: 'capture-probe' })`) with raw hook stdin teed to a scratch file. Map FR5's jq fields to whatever is actually there — specifically: does `tool_input.model` carry the pin; where (if anywhere) does `label` land; does `tool_response` carry an executed-model field. If no model-shaped field exists anywhere in the payload, STOP and rethink FR5 (documented plan deviation). Paste the redacted capture in the PR body (AC0) and encode it as the AC1 test fixture.

### FR5 — Tier-attribution telemetry (ships before pins)

`.claude/hooks/agent-token-tee.sh`:

- **One field:** `model` = executed-model field if Phase 0 found one, else `tool_input.model`, else `"inherit"` (single key; requested-value provenance is recoverable from the pin literal in source — simplicity P2). Semantics per the Phase 0 outcome documented in ADR-053, including the requested-vs-executed limitation if only the request side exists.
- Sanitize like `SUBAGENT_TYPE` (control-char strip + 64-char cap); add to the single jq read pass (~:70-79) and the `line=` builder (~:136-144). **Additive optional key; `schema` stays `1`** (consumer verified key-name-selective).
- Extend `.claude/hooks/agent-token-tee.test.sh` FIRST (cq-write-failing-tests-before): AC0-derived fixture asserts the model key lands; field-absent fixture asserts `"inherit"`.

Disclosure: each workflow with pins gets ONE handwritten `log()` line adjacent to its pins (e.g. `log('tier pins: classify→sonnet, file→haiku')`). No map, no derivation — adjacency in the same diff hunk is the drift control, and the standing allowlist test (FR6) is the mechanical gate. (Resolves the v2 TIER_PINS↔AC2 contradiction by deletion — DHH/simplicity P0, Kieran P1, spec-flow N1.)

### FR1 — Workflow `opts.model` pins (12 call sites, 7 files)

Inline single-quoted pins (`model: 'sonnet'`) with a one-line justification comment per site. Sonnet 4.6 is the workhorse; Haiku only where the runtime prompt is small and template/schema-constrained (TR2).

| File | Pre-edit line (re-locate by `label:`) | Step | Pin | Justification |
|---|---|---|---|---|
| `review/workflows/review.workflow.js` | 401 | `classify` | `sonnet` | Schema-constrained diff-class classification |
| same | 483 | `file` | `haiku` | Template-fill GitHub issue filing from one structured finding |
| `plan-review/workflows/plan-review.workflow.js` | 235 | `detect` | `sonnet` | Schema-constrained plan-shape detection |
| `deepen-plan/workflows/deepen-plan.workflow.js` | 333 | `parse` | `sonnet` | Plan→section-manifest extraction; splice anchors must be exact |
| `resolve-parallel/workflows/resolve-parallel.workflow.js` | 243 | `analyze` | `sonnet` | TODO inventory extraction |
| same | 342 | `commit` | `sonnet` | Commit-message generation over potentially large diffs |
| `resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js` | 236 | `analyze` | `sonnet` | Same class |
| same | 317 | `commit` | `sonnet` | Same class |
| `resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js` | 240 | `fetch` | `haiku` | `gh api` fetch + reformat; small bounded context |
| same | 313 | `commit` | `sonnet` | Commit-message generation |
| `drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js` | 262 | `cluster` | `sonnet` | Issue clustering from structured list |
| same | 355 | `report` | `sonnet` | Markdown report assembly |

**Explicitly NOT pinned (complete — every other `agent()` site in the 8 files):**

- review: `verify` (:379), `concur` (:462), dimension reviewers (:424) — adjudication.
- plan-review: 3 reviewers (:255), consolidate (:276) — judgment.
- **agent-native-audit: both call sites (the 8-audit map at :320-321 and synthesize at :356)** — reconciled against the platform's own precedent: `cron-agent-native-audit.ts:30-31` documents a deliberate sonnet→opus upgrade ("the principle scoring is opus-class reasoning"). The plugin twin of that workload stays `inherit`. Sibling precedents: `cron-competitive-analysis.ts:27`, `cron-legal-audit.ts:25`.
- deepen-plan: N research agents (:389), merge (:415) — judgment.
- resolve-parallel: `plan` (:272) — dependency-tier planning (spec-flow P2.7); N resolvers — code-writing.
- resolve-todo-parallel / resolve-pr-parallel: N resolvers — code-writing.
- drain-labeled-backlog: `brief` (:321), per-cluster `one-shot` (:342) — full pipeline.

### FR2 — Research-spawn guidance (narrowed from spec)

`plugins/soleur/skills/deepen-plan/SKILL.md` only: the verify-the-negative and post-edit self-audit passes (~:325-326; pure grep, ternary verdicts) get a one-line advisory to spawn with the Agent tool's `model: sonnet`. Brainstorm research agents stay `inherit` in v1. **Deliberate narrowing of spec FR2.**

### FR3 — CI pin

`.github/workflows/claude-code-review.yml`: add `claude_args: '--model claude-sonnet-4-6'` to the `claude-code-action` step. Form verified against `test-pretooluse-hooks.yml:76` (same action SHA). Do NOT bump the action SHA.

**Decision (brainstorm Open Question 4):** pin Sonnet, not drift-fix-only. This action is a supplementary advisory commenter; the merge-gating review is the plugin's multi-agent `/soleur:review` (stays `inherit`). The never-downgrade exemption protects the gate, not the advisory pass.

**Execution verification:** `pull_request` workflows run from the PR merge ref, so the pin executes on THIS PR. AC10 pins the check to the head SHA (Kieran P2: `--limit 1` races on multi-push PRs). If the action's logs don't contain the model string, record AC10 as not-verifiable-in-logs and rely on AC3 (the tautological claude_args-echo fallback was dropped — DHH P2).

### FR6 — Policy amendment + standing allowlist test (same PR as pins)

`plugins/soleur/AGENTS.md` Model Selection Policy (~:144-151), replace "no exceptions" with:

1. **Agent frontmatter:** `model: inherit` for ALL agents, unchanged (overrides still need written justification; current exceptions: none).
2. **Workflow call-site pins:** `*.workflow.js` MAY pin `opts.model` at mechanical steps (extract/classify/fetch/commit/file/report) — one-line justification comment per pin; judgment steps (review, verify, synthesis, resolution, implementation, principle scoring) MUST NOT be pinned. Pins are **absolute**: never "one tier below session"; named consequence — a pin can run ABOVE a cheaper session model (Haiku session + sonnet pin); the per-run tier `log()` is the disclosure.
3. **Never-downgrade exemption list:** all `engineering/review/*` agents, data-migration-expert, security/SAST, legal/compliance (clo, gdpr-gate, data-integrity-guardian), C-suite strategy, enumeration-scoring audits, anything gating a merge or touching user data. **The list is enforced mechanically by the pin-allowlist test below; changing the allowlist is a clo-attestation-class change.**

**Standing pin-allowlist test (architecture P1)** — new `plugins/soleur/test/workflow-model-pins.test.ts` (bun test, alongside `components.test.ts`): asserts (a) the set of `model:` occurrences across `plugins/soleur/skills/*/workflows/*.workflow.js` equals the exact 12-entry label→model allowlist above, and (b) `agent-native-audit.workflow.js` contains zero pins. Converts the one-shot AC greps into a permanent gate; a future PR pinning a judgment step fails CI and must deliberately edit the allowlist (precedents: `trigger-cron-allowlist-parity.test.ts`, `seo-aeo-drift-guard.test.ts`).

Also in Phase 1:
- `knowledge-base/project/constitution.md` ~:20 — add `fable` to the enum.
- `plugins/soleur/test/components.test.ts:13` — add `"fable"` to `VALID_MODELS` (architecture P2: constitution/CI divergence otherwise).
- `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md` — records: absolute-pin semantics incl. pin-above-session; allowlist-not-blocklist; FR5 field semantics + requested-vs-executed limitation per Phase 0 outcome; pinned-spawn failure semantics (below); rejected alternatives (frontmatter tiering, session-relative tiers, TIER_PINS map); **pin-surface lifecycle** (architecture P2): plugin enum aliases (`'sonnet'`) are harness-resolved — zero repo maintenance at model deprecation but subject to **silent retargeting** (the harness re-aiming the alias changes every pin's cost/behavior contract with no repo diff; telemetry recording the enum cannot distinguish generations unless Phase 0 found an executed-model field) — vs. CI/Inngest concrete IDs which hard-fail loudly at retirement; #5100 is the re-pin trigger; #5106 owns the Inngest surface.

**Pinned-spawn failure semantics (spec-flow P2.8):** pins have no fallback. A rejected/rate-limited pinned model → `agent()` returns null after retries; fan-outs `.filter(Boolean)`, single steps degrade per each workflow's existing null-handling (`classify` failing aborts the review run — existing behavior). The tee hook drops zero-token envelopes, so **the signature of a rejected pin is absence-of-row, never `model:"inherit"`**.

### Deferred — Inngest cron tier registry → #5106

Cut from this PR at plan review (both panels): independent deploy surface, zero shared code, and the parity AC was unsatisfiable without an unstated `MODEL_PRICING` opus entry. #5106 carries the corrected facts (16 cron/event files incl. `event-ship-merge.ts`; pricing-path scoping; `constants.ts` coverage; mixed alias/dated convention note). Spec FR4 updated to reference the deferral.

## Technical Approach — Implementation Phases

### Phase 0: Empirical capture
- Capture procedure above; evidence in PR body (AC0); fixture encoded (feeds AC1).

### Phase 1: Policy + ADR + enum sync (docs + tests)
- AGENTS.md policy + compliance-checklist line ~125; constitution `fable`; `VALID_MODELS` + `"fable"`; ADR-053.
- Success: AC5, AC8; `bun test plugins/soleur/test/components.test.ts` green.

### Phase 2: Telemetry (FR5)
- `agent-token-tee.test.sh` RED → hook GREEN; consumer-tolerance grep (`grep -n "schema\|total_tokens" plugins/soleur/skills/compound/scripts/token-efficiency-report.sh`).
- Success: AC1.

### Phase 3: Pins (FR1) + allowlist test (FR6) + skill guidance (FR2)
- 12 inline pins + justification comments + one disclosure `log()` per workflow; `workflow-model-pins.test.ts`; deepen-plan SKILL.md advisory.
- Success: AC2, AC4.

### Phase 4: CI pin (FR3)
- One-line `claude_args`; `actionlint` clean; observe this PR's own review run (AC10).

### Phase 5: Acceptance — single tiered run (TR5, narrowed)
- Run the branch's pinned review workflow once on this PR's diff. Assert via the run's TRANSCRIPT (executed-model evidence, ADR-053): pinned spawns show the pinned tiers' concrete IDs, judgment spawns show the session model; `classify`'s diff-class matches this PR's known class (mixed docs+code+CI); `file`-step output (if any findings file) well-formed. The tee JSONL cannot see workflow spawns (AC0).
- **TR5 narrowing recorded (spec-flow P2.9 disposition):** the untiered arm was cut at plan review — n=1 cross-arm agreement of nondeterministic agents is non-probative, rows can't be attributed to arms, and it costs a full Fable-rate review run. The unpinned adjudication layer is the quality safety net by construction. $ attribution assumes the session model (`inherit` rows don't capture it) — state the assumption in the PR-body summary; token counts are the primary metric.
- Success: AC7.

## User-Brand Impact

- **If this lands broken, the user experiences:** a silently degraded mechanical step — e.g. a mis-classified diff runs the wrong review-dimension set, or a malformed auto-filed GitHub issue — discovered only downstream. Mitigated by keeping every adjudication/verification step on `inherit` (the review layer remains the safety net for the execution layer), the standing pin-allowlist test, and the Phase 5 acceptance run.
- **If this leaks, the user's [data / workflow / money] is exposed via:** money — the inverse risk: WITHOUT this change, BYOK operators pay Fable 5 rates (~2-10×) on every mechanical fan-out spawn; WITH a wrong pin (e.g. pinning a judgment step), degraded review recall could ship a defect to the operator's product. No data-exposure vector: model tier changes which Anthropic model processes existing traffic, not what data is sent or to whom.
- **Brand-survival threshold:** `single-user incident` — one missed P1 bug from a downgraded reviewer is brand-fatal; review/security/compliance/scoring paths are exempt by construction AND by the standing allowlist test (FR6.3), not by configuration.

CPO sign-off: satisfied via brainstorm Domain Assessments carry-forward (2026-06-10). `user-impact-reviewer` runs at review time per review skill conditional-agent block.

## Observability

```yaml
liveness_signal:
  what: "per-spawn JSONL envelope (now with model attribution per Phase 0 field mapping) written by agent-token-tee.sh on every Agent PostToolUse"
  cadence: "per-spawn"
  alert_target: "compound Phase 1.6 token-efficiency report (te-* warn incidents -> .claude/.rule-incidents.jsonl -> weekly rule-metrics aggregator)"
  configured_in: ".claude/settings.json PostToolUse Task hook -> .claude/hooks/agent-token-tee.sh"

error_reporting:
  destination: "drop sentinels via _emit_drop_sentinel to .claude/.rule-incidents.jsonl (issue #3509 pattern); hook is fire-and-forget by contract"
  fail_loud: "stderr line 'agent-token-tee: flock timeout, dropping envelope' on write failure; jq_fail/rotation_fail sentinel classes"

failure_modes:
  - mode: "workflow pin dropped before spawn (opts.model not forwarded)"
    detection: "AC0 finding: workflow agent() spawns do NOT fire the tee hook, so the JSONL can never show workflow pins — pre-merge AND post-merge verification of workflow pins is the transcript grep (ADR-053 recipe): grep -ho '\"model\":\"[^\"]*\"' <run-transcript-dir>/agent-*.jsonl | sort | uniq -c; a pinned spawn showing the session model = dropped pin. The JSONL jq below covers DIRECT Agent-tool spawns only."
    alert_route: "Phase 5 acceptance gate pre-merge; post-merge: operator-run discoverability test"
  - mode: "pin forwarded but ignored/substituted by backend (requested != executed)"
    detection: "Phase 0 determines whether an executed-model field exists; if yes, the recorded field IS the executed model; if no, this mode is undetectable in telemetry — documented ADR limitation"
    alert_route: "ADR-053 limitation note; #5100 re-evaluation"
  - mode: "pinned model rejected (429/enum) — spawn dies, zero-token envelope dropped"
    detection: "absence-of-row for an expected spawn is the signature (NOT model=inherit); workflow null-handling logs the failed step"
    alert_route: "workflow run output (operator-visible) at run time"
  - mode: "future PR pins a judgment step (never-downgrade violation)"
    detection: "workflow-model-pins.test.ts allowlist mismatch"
    alert_route: "CI failure pre-merge"

logs:
  where: ".claude/.session-tokens.jsonl (gitignored, shared rotator via lib/log-rotation.sh)"
  retention: "rotated archives per log-rotation.sh policy"

discoverability_test:
  command: bash .claude/hooks/agent-token-tee.test.sh
  expected_output: "0 failed"
  # Deterministic mechanism check (17 tests incl. model-attribution fixtures), ~7s local, no ssh/pipes.
  # Live-state reads: direct-spawn rows via jq on .claude/.session-tokens.jsonl (repo root);
  # workflow-pin executed-model via the ADR-053 transcript grep (tee JSONL cannot show workflow spawns - AC0).
```

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC0: Phase 0 capture evidence recorded. Finding: PostToolUse does NOT fire for Workflow-runtime agent() spawns (JSONL row-count diff around probe run wf_0c2aa99a); the executed model IS recorded in the workflow transcript (`"model":"claude-haiku-4-5-20251001"` for the pinned probe). FR5 field mapping: `.tool_input.model // "inherit"` (direct spawns only).
- [x] AC1: `bash .claude/hooks/agent-token-tee.test.sh` passes, including the AC0-derived fixture (model present → recorded) and field-absent fixture (→ `"inherit"`).
- [x] AC2: `grep -hoE "model: '(sonnet|haiku)'" plugins/soleur/skills/*/workflows/*.workflow.js | wc -l` prints `12`; `grep -coE "model: '(sonnet|haiku)'" plugins/soleur/skills/review/workflows/review.workflow.js` prints `2`; `grep -c "model: '" plugins/soleur/skills/agent-native-audit/workflows/agent-native-audit.workflow.js` prints `0` (and exits 1 — expected for a zero count).
- [x] AC3: `actionlint .github/workflows/claude-code-review.yml` exits 0; `grep -c "claude_args: '--model claude-sonnet-4-6'" .github/workflows/claude-code-review.yml` prints `1`.
- [x] AC4: `bun test plugins/soleur/test/workflow-model-pins.test.ts` green (12-entry allowlist match + zero pins in agent-native-audit).
- [x] AC5: `plugins/soleur/AGENTS.md` policy section contains the three-tier vocabulary and no longer contains the literal `for all agents, no exceptions`; every pin line has an adjacent justification comment (spot-check cited in PR body).
- [x] AC6: `bun test plugins/soleur/test/components.test.ts` green with `"fable"` in `VALID_MODELS`.
- [x] AC7: Phase 5 single-arm acceptance: the acceptance run's workflow TRANSCRIPT (`grep -ho '"model":"[^"]*"' <run-transcript-dir>/agent-*.jsonl | sort | uniq -c`) shows the pinned tiers' concrete model IDs on `classify`/`file`-class spawns and the session model on judgment spawns (AC0 finding: the JSONL channel cannot see workflow spawns); `classify` returns this PR's known diff-class; summary in PR body.
- [x] AC8: ADR-053 exists (incl. pin-above-session, silent-retarget lifecycle, requested-vs-executed limitation, failure semantics); constitution ~:20 includes `fable`.
- [x] AC9: deepen-plan SKILL.md carries the FR2 advisory bullet (one line, verify-the-negative + self-audit passes only).
- [x] AC10 (disposition: not-verifiable-by-construction): `claude-code-review.yml` is `disabled_manually` in repo Actions settings (no runs since 2026-02-12), so no run can exercise the pin. The pin is dormant-but-correct (AC3 verifies the form against the working `test-pretooluse-hooks.yml:76` precedent) and makes re-enabling affordable — re-enabling is an operator spend decision surfaced in the PR body.

### Post-merge (operator)

None — all steps automatable in-PR (CI pin exercised on this PR per AC10; no web-platform deploy surface in this PR).

## Test Scenarios

- Given the AC0-captured payload with the model field present, when the tee hook processes it, then the JSONL record contains the model value (AC1).
- Given a payload without the field, when processed, then the record contains `"inherit"` (AC1).
- Given a future PR adds `model: 'haiku'` to review `verify`, when CI runs, then `workflow-model-pins.test.ts` fails (AC4 standing gate).
- Given the pinned review workflow runs on this PR's diff, when `classify` executes, then telemetry attributes the pinned model and the diff-class matches this PR's known class (AC7).
- Given a Sonnet session, when a pinned `haiku` step runs, then it runs Haiku (absolute pin).
- Given a Haiku session, when a pinned `sonnet` step runs, then it runs Sonnet — cost upgrade above session tier, disclosed via the tier `log()` (ADR-053 named consequence).
- Given a pinned model is rejected at spawn (429/enum), when the workflow continues, then absence-of-telemetry-row plus the workflow's null-handling log is the observable signature (no false `inherit` row).

## Domain Review

**Domains relevant:** Engineering, Product, Legal, Finance (carry-forward from brainstorm `## Domain Assessments`, 2026-06-10)

### Engineering (CTO)

**Status:** reviewed (carry-forward)
**Assessment:** Tier via workflow `opts.model` at allowlisted mechanical steps; frontmatter untouched; judgment paths exempt; telemetry-first phasing; policy + pins in one PR; ADR recommended (ADR-053).

### Legal (CLO)

**Status:** reviewed (carry-forward)
**Assessment:** No published commitment names a model tier; hard exemption list required for compliance/security/attestation agents (FR6.3 — now mechanically enforced); operator visibility required (FR5 disclosure); BYOK billable-run tiering deferred to #5099 with three-doc lockstep.
**gdpr-gate (plan Phase 2.7, trigger b):** ran 2026-06-10 — no findings at any severity; no regulated-data surface touched; no new vendor/transfer (same processor, different model parameter); telemetry addition is local-only operational metadata. Re-run if scope expands to BYOK billable runs.

### Finance (CFO)

**Status:** reviewed (carry-forward)
**Assessment:** Operator Max seats are flat-rate (savings = quota headroom); BYOK users get ~65-80% per-fan-out savings; input-side context re-reads dominate; measurement = telemetry JSONL (Phase 5, session-model assumption caveat for $ attribution).

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI-surface files in Files lists; mechanical override did not fire.
**Brainstorm-recommended specialists:** spec-flow-analyzer (CPO) — invoked twice (pre-review + 5-agent panel re-validation); 13/16 v1 findings verified FIXED, 2 PAPER findings resolved in v3 by deletion (TIER_PINS, FR4), 3 untraceable findings given explicit dispositions (P2.9: TR5 narrowing recorded in Phase 5; P3.14: pin style fixed single-quote in Sharp Edges; P3.15: AC2/AC10 exit-code semantics stated inline).
**Pencil available:** N/A (no UI surface)

### Plan-review panel (5-agent, 2026-06-10)

DHH + code-simplicity (simplification axis) and Kieran + architecture-strategist + spec-flow (correctness axis). Convergent verdicts applied: TIER_PINS deleted; FR4 → #5106; Phase 6 → single arm; standing allowlist test added; VALID_MODELS sync; ADR lifecycle content; AC mechanics fixed. Verified clean by Kieran: 12-pin enumeration complete and line-accurate (all 27 sites), tee-hook edit shape, AC10 merge-ref semantics, opus-precedent citations.

## Open Code-Review Overlap

- #4133 (schema parity test for `## Observability` block) cites `deepen-plan/SKILL.md`, which this plan also edits. **Disposition: Acknowledge** — orthogonal concern (parity test vs one-line research-spawn advisory); remains open; no collision.

## Files to Edit

1. `plugins/soleur/skills/review/workflows/review.workflow.js` — inline pins at `classify`/`file` + disclosure log
2. `plugins/soleur/skills/plan-review/workflows/plan-review.workflow.js` — pin at `detect` + log
3. `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js` — pin at `parse` + log
4. `plugins/soleur/skills/resolve-parallel/workflows/resolve-parallel.workflow.js` — pins at `analyze`/`commit` + log
5. `plugins/soleur/skills/resolve-todo-parallel/workflows/resolve-todo-parallel.workflow.js` — pins at `analyze`/`commit` + log
6. `plugins/soleur/skills/resolve-pr-parallel/workflows/resolve-pr-parallel.workflow.js` — pins at `fetch`/`commit` + log
7. `plugins/soleur/skills/drain-labeled-backlog/workflows/drain-labeled-backlog.workflow.js` — pins at `cluster`/`report` + log
8. `plugins/soleur/skills/deepen-plan/SKILL.md` — FR2 advisory bullet
9. `.github/workflows/claude-code-review.yml` — `claude_args` pin
10. `.claude/hooks/agent-token-tee.sh` — `model` field
11. `.claude/hooks/agent-token-tee.test.sh` — fixtures (RED first)
12. `plugins/soleur/AGENTS.md` — policy amendment + compliance-checklist line
13. `plugins/soleur/test/components.test.ts` — `VALID_MODELS` + `"fable"`
14. `knowledge-base/project/constitution.md` — ~:20 add `fable`
15. `knowledge-base/project/specs/feat-model-tier-optimization/spec.md` — FR4 deferral note + TR5 narrowing `[Updated 2026-06-10]`

(NOT edited: `agent-native-audit.workflow.js` — exemption; all `apps/web-platform/**` — deferred to #5106.)

## Files to Create

1. `plugins/soleur/test/workflow-model-pins.test.ts` — standing pin-allowlist gate
2. `knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| `tool_input.model` absent for workflow spawns (telemetry chain broken) | Phase 0 capture BEFORE any code; STOP branch = documented FR5 rewrite, not a silent gap |
| Pin forwarded but ignored by backend (requested ≠ executed) | Phase 0 checks for an executed-model field; if none, ADR documents the limitation (telemetry proves request, not execution) |
| Quality regression on a pinned mechanical step | Pins limited to extract/classify/fetch/commit/file/report; unpinned review layer is the downstream safety net; Phase 5 spot-check |
| Future PR pins a judgment step | `workflow-model-pins.test.ts` standing allowlist gate (CI-blocking) |
| Haiku context overflow on `fetch`/`file` | Both consume bounded structured inputs; Sonnet everywhere else (TR2) |
| Policy/practice drift | FR6 + pins land in one PR; allowlist test makes the policy mechanical |
| Tee hook schema consumers break | Additive optional key, `schema:1` retained; consumer grep in Phase 2 |
| Harness silently retargets the `sonnet`/`haiku` aliases at a future model release | ADR-053 lifecycle note; #5100 (model-launch-review) is the re-pin trigger |
| `claude-code-action` rejects the pinned model string | Form verified against working `test-pretooluse-hooks.yml:76`; AC10 observes the actual run on this PR |
| Pinned model unavailable at run time (429/enum drift) | No fallback by design; failure semantics in ADR; absence-of-row signature |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6 — complete above.
- Pin style is single-quoted `model: 'sonnet'` (matches workflow-script string style); AC2's regex and the allowlist test depend on it (spec-flow P3.14 disposition).
- Pin line numbers are pre-edit references; /work re-locates by `label:` string.
- Workflow scripts are self-contained (no imports) — pins are inline per-site literals, never a shared map or import; justification comment per site.
- The rejected-pin signature is **absence-of-row** in telemetry (zero-token envelopes dropped by design), never `model:"inherit"`.
- `grep -c` prints `0` AND exits 1 on zero matches — AC2's third command and any `&&` chain must account for it (spec-flow P3.15 disposition).
- Do NOT touch `apps/web-platform/**` in this PR — the Inngest surface is #5106's.

## References & Research

- Spec: `knowledge-base/project/specs/feat-model-tier-optimization/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-06-10-model-tier-optimization-brainstorm.md`
- Policy provenance: PR #295 / `knowledge-base/project/brainstorms/archive/2026-02-24-model-policy-brainstorm.md`
- Prior decisions: `knowledge-base/project/brainstorms/2026-04-13-token-optimization-brainstorm.md` (gating-not-downgrades; superseded for mechanical steps by this plan)
- PostToolUse payload shape: `knowledge-base/project/learnings/2026-05-10-claude-code-posttooluse-task-hook-input-shape.md` (Phase 0 capture basis)
- Learnings: `knowledge-base/project/learnings/2026-02-22-model-id-update-patterns.md`, `knowledge-base/project/learnings/2026-04-18-action-pin-sync-with-model-bump.md`, `knowledge-base/project/learnings/2026-05-11-token-budget-heuristic-must-model-runtime-prompt-not-full-skill-md.md`, `knowledge-base/project/learnings/2026-06-10-model-economics-brainstorm-dormant-triggers-and-pricing-source.md`
- Issues: #3791 (closes), #2030 (complement), #5099/#5100/#5106 (deferred follow-ups), #4133 (acknowledged overlap)
- Pricing (verified via claude-api reference, cached 2026-05-26): Fable 5 $10/$50, Opus 4.8 $5/$25, Sonnet 4.6 $3/$15, Haiku 4.5 $1/$5 per MTok
